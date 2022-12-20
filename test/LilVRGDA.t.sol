// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import {LilVRGDA} from "../src/LilVRGDA.sol";
import {LilNounsUnitTest} from "./helpers/LilNounsUnitTest.sol";

// MockWETHReceiver can call settleAuction,
// but does not support receiving ether (for refunds)
// so it must use WETH fallback
contract MockWETHReceiver {
    LilVRGDA internal immutable vrgda;

    constructor(address _lilVRGDAAddress) {
        vrgda = LilVRGDA(_lilVRGDAAddress);
    }

    function callSettleAuction(
        uint256 expectedNounId,
        bytes32 expectedParentBlockhash
    ) external payable {
        vrgda.settleAuction{value: msg.value}(
            expectedNounId,
            expectedParentBlockhash
        );
    }
}

contract LilVRGDATest is LilNounsUnitTest {
    uint256 targetPrice = 0.15e18;

    function setUp() public {
        deploy(
            int256(targetPrice), // Target price.
            0.31e18, // Price decay percent.
            24 * 4 * 1e18, // Per time unit.
            block.timestamp, // auction start time
            0 // reservePrice
        );
        populateDescriptor();

        // Set block.timestamp to something ahead of vrgda.startTime()
        vm.warp(vrgda.startTime() + 1 days);
    }

    receive() external payable {}

    function testSettleAuction() public {
        uint256 initialNextNounId = vrgda.nextNounId();
        uint256 initialBalance = address(this).balance;

        // Caller should own no nouns at start.
        assertEq(nounsToken.balanceOf(address(this)), 0);
        (uint256 nounId, , , uint256 price, bytes32 hash) = vrgda
            .fetchNextNoun();

        vm.expectEmit(false, true, true, true);
        vrgda.settleAuction{value: price}(nounId, hash);

        // A noun should have been minted to nounders
        assertEq(nounsToken.ownerOf(initialNextNounId), noundersDAOAddress);
        // A noun should have been minted to the DAO
        assertEq(nounsToken.ownerOf(initialNextNounId + 1), nounsDAOAddress);
        // A noun should have been minted to caller that settled the auction
        assertEq(nounsToken.balanceOf(address(this)), 1);
        assertEq(nounsToken.ownerOf(initialNextNounId + 2), address(this));
        assertEq(initialNextNounId + 2, nounId);

        // VRGDA contract should nextNounId to reflect the 3 sales
        assertEq(vrgda.nextNounId(), initialNextNounId + 3);

        // Value equal to the auction price should be transferred to DAO
        assertEq(nounsDAOAddress.balance, price);
        assertEq(weth.balanceOf(nounsDAOAddress), 0);

        // Value equal to the auction price should be transferred to DAO
        assertEq(address(vrgda).balance, 0);
        assertEq(weth.balanceOf(address(vrgda)), 0);

        assertEq(address(this).balance, initialBalance - price);
        assertEq(weth.balanceOf(address(this)), 0);

        // Attempts to mint the same noun this block should fail
        vm.expectRevert("Invalid or expired nounId");
        vrgda.settleAuction(nounId, hash);

        // However, attempts to mint using the next ID with the same hash should pass 👀
        (uint256 newNounId, , , uint256 newPrice, ) = vrgda.fetchNextNoun(); // Fetch updated NounId and price after earlier sale
        assertEq(newNounId, nounId + 1);
        assertGt(newPrice, price);
        vrgda.settleAuction{value: newPrice}(newNounId, hash); // Note: hash unchanged
    }

    function testSettleAuctionOverageRefund() public {
        uint256 initialBalance = address(this).balance;
        (uint256 nounId, , , uint256 price, bytes32 hash) = vrgda
            .fetchNextNoun();
        assertGt(price, 0);
        uint256 overage = 1 ether;
        vrgda.settleAuction{value: price + overage}(nounId, hash);
        assertEq(nounsToken.ownerOf(nounId), address(this));

        // Value equal to the auction price should be transferred to DAO
        assertEq(nounsDAOAddress.balance, price);
        assertEq(weth.balanceOf(nounsDAOAddress), 0);

        // Value equal to the auction price should be transferred to DAO
        assertEq(address(vrgda).balance, 0);
        assertEq(weth.balanceOf(address(vrgda)), 0);

        // Overage should be refunded back to caller
        assertEq(address(this).balance, initialBalance - price);
        assertEq(weth.balanceOf(address(this)), 0);
    }

    function testSettleAuctionOverageRefundWETH() public {
        MockWETHReceiver wethReceiver = new MockWETHReceiver(address(vrgda));
        (uint256 nounId, , , uint256 price, bytes32 hash) = vrgda
            .fetchNextNoun();

        uint256 overage = 1 ether;
        wethReceiver.callSettleAuction{value: price + overage}(nounId, hash);
        assertEq(address(wethReceiver).balance, 0);
        assertEq(weth.balanceOf(address(wethReceiver)), overage);
    }

    function testSettleAuctionExpiredBlockhash() public {
        (uint256 nounId, , , uint256 price, ) = vrgda.fetchNextNoun();

        // Should revert if incorrect blockhash supplied
        vm.expectRevert("Invalid or expired blockhash");
        vrgda.settleAuction{value: price}(nounId, keccak256(unicode"⌐◨-◨ "));
    }

    function testSettleAuctionExpiredNounId() public {
        (uint256 nounId, , , uint256 price, bytes32 hash) = vrgda
            .fetchNextNoun();

        // Should revert if incorrect nounId supplied
        vm.expectRevert("Invalid or expired nounId");
        vrgda.settleAuction{value: price}(nounId + 1, hash);
    }

    function testSettleAuctionInsufficientFunds() public {
        (uint256 nounId, , , uint256 price, bytes32 hash) = vrgda
            .fetchNextNoun();

        // Should revert if value supplied is lower than VRGDA price
        vm.expectRevert("Insufficient funds");
        vrgda.settleAuction{value: price - 1}(nounId, hash);
    }

    function testReservePrice() public {
        // Non owners cannot set reservePrice
        vm.prank(address(999));
        vm.expectRevert("Ownable: caller is not the owner");
        vrgda.setReservePrice(1 ether);

        // Owners can set reservePrice
        vm.prank(nounsDAOAddress); // Call as owner
        vrgda.setReservePrice(1 ether);
        (uint256 nounId, , , , bytes32 hash) = vrgda.fetchNextNoun();

        // Should revert if supplied price is not high enough
        vm.prank(address(this));
        vm.expectRevert("Below reservePrice");
        vrgda.settleAuction{value: 1 ether - 1}(nounId, hash);

        // Should be able to settle the auction once reserve price is lowered
        vm.prank(nounsDAOAddress); // Call as owner
        vrgda.setReservePrice(0.5 ether);
        vrgda.settleAuction{value: 1 ether}(nounId, hash);
    }

    function testSetUpdateInterval() public {
        // Non owners cannot set updateInterval
        vm.prank(address(999));
        vm.expectRevert("Ownable: caller is not the owner");
        vrgda.setUpdateInterval(1 minutes);

        // Owners can set updateInterval
        vm.prank(nounsDAOAddress); // Call as owner
        vrgda.setUpdateInterval(1 minutes);
        assertEq(vrgda.updateInterval(), 1 minutes);
    }

    function testSetTargetPrice() public {
        // Non owners cannot set targetPrice
        vm.prank(address(999));
        vm.expectRevert("Ownable: caller is not the owner");
        vrgda.setTargetPrice(1 ether);

        // Owners can set targetPrice
        vm.prank(nounsDAOAddress); // Call as owner
        vrgda.setTargetPrice(1 ether);
        assertEq(vrgda.targetPrice(), 1 ether);
    }

    function testSetPriceDecayPercent() public {
        int256 initialDecayConstant = vrgda.decayConstant();

        // Non owners cannot set priceDecayPercent
        vm.prank(address(999));
        vm.expectRevert("Ownable: caller is not the owner");
        vrgda.setPriceDecayPercent(1);

        // Owners can set priceDecayPercent
        vm.prank(nounsDAOAddress); // Call as owner
        vrgda.setPriceDecayPercent(1);
        assertFalse(vrgda.decayConstant() == initialDecayConstant);
    }

    function testSetPerTimeUnit() public {
        // Non owners cannot set perTimeUnit
        vm.prank(address(999));
        vm.expectRevert("Ownable: caller is not the owner");
        vrgda.setPerTimeUnit(1);

        // Owners can set perTimeUnit
        vm.prank(nounsDAOAddress); // Call as owner
        vrgda.setPerTimeUnit(1);
        assertEq(vrgda.perTimeUnit(), 1);
    }

    function testPause() public {
        // Contract should not be paused to start
        assertFalse(vrgda.paused());

        // Non owners can't pause
        vm.prank(address(999));
        vm.expectRevert("Ownable: caller is not the owner");
        vrgda.pause();

        // Owner can pause
        vm.prank(nounsDAOAddress);
        vrgda.pause();

        // settleAuction should fail if paused
        (uint256 nounId, , , uint256 price, bytes32 hash) = vrgda
            .fetchNextNoun();
        vm.expectRevert("Pausable: paused");
        vrgda.settleAuction{value: price}(nounId, hash);
    }

    function testRejectsEther() public {
        // VRGDA contract should transactions with ether value with calldata sent to fallback
        vm.expectRevert("Revert");
        (bool sent, ) = payable(address(vrgda)).call{value: 1 ether}(
            "calldata"
        );
        assertFalse(sent);

        // VRGDA contract should transactions with ether value and no calldata sent to fallback
        vm.expectRevert("revert");
        (sent, ) = payable(address(vrgda)).call{value: 1 ether}(new bytes(0));
        assertFalse(sent);
    }

    function testVRGDAPricing() public {
        // The rest of the test relies on this assumption
        assertGt(vrgda.updateInterval(), 1 seconds);

        vm.warp(vrgda.startTime());
        uint256 initialPrice = vrgda.getCurrentVRGDAPrice();
        // Price should be higher than target at first, until 1 full time interval
        // has passed
        assertGt(initialPrice, targetPrice);

        // Price should stay the same for the entire interval
        vm.warp(vrgda.startTime() + vrgda.updateInterval() - 1 seconds);
        uint256 priceOneSecondBeforeUpdate = vrgda.getCurrentVRGDAPrice();
        assertEq(initialPrice, priceOneSecondBeforeUpdate);

        // Price should update at and after the update interval
        vm.warp(vrgda.startTime() + vrgda.updateInterval());
        uint256 priceAtUpdate = vrgda.getCurrentVRGDAPrice();
        vm.warp(vrgda.startTime() + vrgda.updateInterval() + 1 seconds);
        uint256 priceOneSecondAfterUpdate = vrgda.getCurrentVRGDAPrice();
        assertEq(priceAtUpdate, priceOneSecondAfterUpdate);
        assertGt(priceOneSecondBeforeUpdate, priceAtUpdate);

        // At the first interval price should be target price (assuming no sales)
        assertEq(targetPrice, priceAtUpdate);
    }
}
