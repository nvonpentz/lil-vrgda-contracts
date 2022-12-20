import {console} from "hardhat/console.sol";
import {Test} from "forge-std/Test.sol";
import {INounsSeeder} from "lil-nouns-contracts/interfaces/INounsSeeder.sol";
import {NounsSeederV2} from "../src/NounsSeederV2.sol";
import {LilNounsUnitTest} from "./helpers/LilNounsUnitTest.sol";

pragma solidity ^0.8.17;

contract NounsSeederV2UnitTest is LilNounsUnitTest {
    uint256 targetPrice = 0.15e18;
    NounsSeederV2 seederV2;
    uint256 initialNounId = 0;

    function setUp() public {
        deploy(
            int256(targetPrice), // Target price.
            0.31e18, // Price decay percent.
            24 * 4 * 1e18, // Per time unit.
            initialNounId, // ID of the noun last sold
            block.timestamp, // auction start time
            0 // reservePrice
        );
        populateDescriptor();
        // set block number to 7
        vm.roll(1000);
    }

    function seedsEqual(
        INounsSeeder.Seed memory s1,
        INounsSeeder.Seed memory s2
    ) internal pure returns (bool equal) {
        return
            s1.background == s2.background &&
            s1.body == s2.body &&
            s1.accessory == s2.accessory &&
            s1.head == s2.head &&
            s1.glasses == s2.glasses;
    }

    function testGetUpdateInterval() public {
        seederV2 = new NounsSeederV2(address(nounsToken));

        // Should return the default update interval
        assertTrue(seederV2.getUpdateInterval() == 1);

        // Should return the updated update interval
        seederV2.setUpdateInterval(2);
        assertTrue(seederV2.getUpdateInterval() == 2);
    }

    function testSetInterval() public {
        seederV2 = new NounsSeederV2(address(nounsToken));

        // Should revert if caller is not the owner of nouns token
        vm.expectRevert("Caller is not the owner of nouns token");
        vm.prank(address(555));
        seederV2.setUpdateInterval(100);

        // Should not revert if caller is the owner of nouns token
        seederV2.setUpdateInterval(100);

        // Should revert if interval is 0
        vm.expectRevert("Update interval must be greater than 0");
        seederV2.setUpdateInterval(0);
    }

    function testGenerateSeed() public {
        seederV2 = new NounsSeederV2(address(nounsToken));

        // SeederV1 and SeederV2 should return the same seed when update interval=1 (default)
        for (uint256 i = 0; i < 1 * seederV2.getUpdateInterval(); i++) {
            INounsSeeder.Seed memory v1seed = seeder.generateSeed(
                initialNounId,
                descriptor
            );
            INounsSeeder.Seed memory v2seed = seederV2.generateSeed(
                initialNounId,
                descriptor
            );
            assertTrue(seedsEqual(v1seed, v2seed));
            vm.roll(block.number + 1);
        }

        // Update the update interval to 2
        seederV2.setUpdateInterval(2);

        // SeederV1 and SeederV2 should return the different seeds for odd blocks when update interval=2
        for (uint256 i = 0; i < 1 * seederV2.getUpdateInterval(); i++) {
            INounsSeeder.Seed memory v1seed = seeder.generateSeed(
                initialNounId,
                descriptor
            );
            INounsSeeder.Seed memory v2seed = seederV2.generateSeed(
                initialNounId,
                descriptor
            );
            if (block.number % 2 == 0) {
                assertTrue(seedsEqual(v1seed, v2seed));
            } else {
                assertTrue(!seedsEqual(v1seed, v2seed));
            }
            vm.roll(block.number + 1);
        }
    }
}

// RoundToNearestUnitTest is for unit testing internal functions
// for NounsSeederV2
contract RoundToNearestUnitTest is Test, NounsSeederV2 {
    constructor() NounsSeederV2(address(0)) {}

    function testRoundToNearest() public {
        assertEq(roundToNearest(0, 1), 0);
        assertEq(roundToNearest(1, 1), 1);
        assertEq(roundToNearest(2, 1), 2);
        assertEq(roundToNearest(3, 1), 3);
        assertEq(roundToNearest(4, 1), 4);
        assertEq(roundToNearest(5, 1), 5);
        assertEq(roundToNearest(6, 1), 6);
        assertEq(roundToNearest(7, 1), 7);
        assertEq(roundToNearest(8, 1), 8);
        assertEq(roundToNearest(9, 1), 9);
        assertEq(roundToNearest(10, 1), 10);

        assertEq(roundToNearest(0, 2), 0);
        assertEq(roundToNearest(1, 2), 0);
        assertEq(roundToNearest(2, 2), 2);
        assertEq(roundToNearest(3, 2), 2);
        assertEq(roundToNearest(4, 2), 4);
        assertEq(roundToNearest(5, 2), 4);
        assertEq(roundToNearest(6, 2), 6);
        assertEq(roundToNearest(7, 2), 6);
        assertEq(roundToNearest(8, 2), 8);
        assertEq(roundToNearest(9, 2), 8);
        assertEq(roundToNearest(10, 2), 10);

        assertEq(roundToNearest(0, 3), 0);
        assertEq(roundToNearest(1, 3), 0);
        assertEq(roundToNearest(2, 3), 0);
        assertEq(roundToNearest(3, 3), 3);
        assertEq(roundToNearest(4, 3), 3);
        assertEq(roundToNearest(5, 3), 3);
        assertEq(roundToNearest(6, 3), 6);
        assertEq(roundToNearest(7, 3), 6);
        assertEq(roundToNearest(8, 3), 6);
        assertEq(roundToNearest(9, 3), 9);
        assertEq(roundToNearest(10, 3), 9);
    }
}
