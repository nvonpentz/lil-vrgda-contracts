// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { LinearVRGDA } from "VRGDAs/LinearVRGDA.sol";
import { NounsToken } from "lil-nouns-contracts/NounsToken.sol";
import { INounsSeeder } from "lil-nouns-contracts/interfaces/INounsSeeder.sol";
import { INounsDescriptor } from "lil-nouns-contracts/interfaces/INounsDescriptor.sol";
import { ILilVRGDA } from "./interfaces/ILilVRGDA.sol";

import { Pausable } from '@openzeppelin/contracts/security/Pausable.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

import { IWETH } from "lil-nouns-contracts/interfaces/IWETH.sol";
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { toDaysWadUnsafe } from "solmate/utils/SignedWadMath.sol";
// import { console } from "forge-std/console.sol";

// Functions should be grouped according to their visibility and ordered:
// * constructor
// * receive function (if exists)
// * fallback function (if exists)
// * external
// * public
// * internal
// * private
// sub order is (state-modifiable, then view, then pure within each group)


// contract LilVRGDA is ILilVRGDA, LinearVRGDA  { // TODO review how the order of inheritance matters
contract LilVRGDA is ILilVRGDA, LinearVRGDA, Pausable, ReentrancyGuard, Ownable {
    uint256 public nextNounId; // The total number sold + 1
    uint256 public immutable startTime; // When VRGDA sales begun.
    uint256 public immutable updateInterval = 15 minutes;

    // The minimum price accepted in an auction
    uint256 public reservePrice;

    NounsToken public immutable nounsToken;
    address public immutable wethAddress;

    constructor(
        int256 _targetPrice,
        int256 _priceDecayPercent,
        int256 _perTimeUnit,
        uint256 _nextNounId,
        uint256 _startTime,
        address _nounsTokenAddress,
        address _wethAddress,
        uint256 _reservePrice
    ) LinearVRGDA(_targetPrice, _priceDecayPercent, _perTimeUnit) {
        nounsToken = NounsToken(_nounsTokenAddress);
        nextNounId = _nextNounId;
        startTime = _startTime;
        wethAddress = _wethAddress;
        reservePrice = _reservePrice;
    }

    // TODO initialize function
    function settleAuction(uint expectedNounId, bytes32 expectedParentBlockhash) external payable override whenNotPaused nonReentrant {
        // Only settle if desired Noun would be minted
        bytes32 parentBlockhash = blockhash(block.number - 1);
        require(expectedParentBlockhash == parentBlockhash, "Invalid or expired blockhash");
        uint _nextNounIdForCaller = nextNounIdForCaller();
        require(expectedNounId == _nextNounIdForCaller, "Invalid or expired nounId");
        require(msg.value >= reservePrice, "Below reservePrice");

        // Validate the purchase request against the VRGDA rules.
        // uint256 price = getVRGDAPrice(toDaysWadUnsafe(block.timestamp - startTime), nextNounId);
        uint256 price = getCurrentVRGDAPrice();
        require(msg.value >= price, "Insufficient funds");

        // Call settleAuction on the nouns contract.
        uint256 mintedNounId = nounsToken.mint();
        assert(mintedNounId == _nextNounIdForCaller);

        // Sends token to caller.
        nounsToken.transferFrom(address(this), msg.sender, mintedNounId);

        // Sends the funds to the DAO.
        if (msg.value > 0) {
            uint refundAmount = msg.value - price;
            if (refundAmount > 0) {
                _safeTransferETHWithFallback(msg.sender, refundAmount);
            }
            if (price > 0) {
                _safeTransferETHWithFallback(address(2), price); // TODO replace with DAO address or make ownable by DAO
            }
        }

        nextNounId = mintedNounId+1;
        emit AuctionSettled(mintedNounId, msg.sender, price);
    }

    /**
     * @notice Set the auction reserve price.
     * @dev Only callable by the owner.
     */
    function setReservePrice(uint256 _reservePrice) external onlyOwner {
        reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_reservePrice);
    }

    /**
     * @notice Pause the Nouns auction house.
     * @dev This function can only be called by the owner when the
     * contract is unpaused. While no new auctions can be started when paused,
     * anyone can settle an ongoing auction.
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the Nouns auction house.
     * @dev This function can only be called by the owner when the
     * contract is paused. If required, this function will start a new auction.
     */
    function unpause() external override onlyOwner {
        _unpause();
    }

    function fetchNextNoun() external view override returns (
        uint256 nounId,
        INounsSeeder.Seed memory seed,
        string memory svg,
        uint256 price,
        bytes32 hash
    ) {
        uint _nextNounIdForCaller = nextNounIdForCaller();
        // Generate the seed for the next noun.
        INounsSeeder seeder = INounsSeeder(nounsToken.seeder());
        INounsDescriptor descriptor = INounsDescriptor(nounsToken.descriptor());
        seed = seeder.generateSeed(
            _nextNounIdForCaller,
            descriptor
        );

        // Generate the SVG from seed using the descriptor.
        svg = descriptor.generateSVGImage(seed);

        // Calculate price based on VRGDA rules.
        price = getCurrentVRGDAPrice();

        // Fetch the blockhash associated with this noun.
        hash = blockhash(block.number-1);

        return (_nextNounIdForCaller, seed, svg, price, hash);
    }

    // Note: I can keep this function and still test by having my
    // tests inherit from this contract
    function getCurrentVRGDAPrice() public view returns (uint256) {
        uint absoluteTimeSinceStart = block.timestamp - startTime;
        return getVRGDAPrice(toDaysWadUnsafe(absoluteTimeSinceStart - (absoluteTimeSinceStart % updateInterval)), nextNounId);
    }

    // @dev handles edge case in nouns token contract
    function nextNounIdForCaller() public view returns (uint256) {
        // Calculate nounId that would be minted to the caller
        uint _nextNounIdForCaller = nextNounId;
        if (_nextNounIdForCaller <= 175300  && _nextNounIdForCaller % 10 == 0) {
            _nextNounIdForCaller++;
        }
        if (_nextNounIdForCaller <= 175301 && _nextNounIdForCaller % 10 == 1) {
            _nextNounIdForCaller ++;
        }
        return _nextNounIdForCaller;
    }

    /**
     * @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and try send it as wethAddress.
     */
    function _safeTransferETHWithFallback(address to, uint256 amount) internal {
        if (!_safeTransferETH(to, amount)) {
            IWETH(wethAddress).deposit{ value: amount }();
            IERC20(wethAddress).transfer(to, amount);
        }
    }

    /**
     * @notice Transfer ETH and return the success status.
     * @dev This function only forwards 30,000 gas to the callee.
     */
    function _safeTransferETH(address to, uint256 value) internal returns (bool) {
        (bool success, ) = to.call{ value: value, gas: 30_000 }(new bytes(0));
        return success;
    }
}
