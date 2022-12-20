import {console} from "hardhat/console.sol";
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

    function testSetInterval() public {
        seederV2 = new NounsSeederV2(address(nounsToken));

        // Should revert if caller is not the owner of nouns token
        vm.expectRevert("Caller is not the owner of nouns token");
        vm.prank(address(555));
        seederV2.setUpdateInterval(100);

        // Should not revert if caller is the owner of nouns token
        seederV2.setUpdateInterval(100);
    }

    function testGenerateSeed() public {
        seederV2 = new NounsSeederV2(address(nounsToken));

        // SeederV1 and SeederV2 should return the same seed when update interval=1 (default)
        for (uint256 i = 0; i < 1 * seederV2.updateInterval(); i++) {
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
        for (uint256 i = 0; i < 1 * seederV2.updateInterval(); i++) {
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
