// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import {LilVRGDAV2} from "../src/LilVRGDAV2.sol";
import {NounsSeederV2} from "../src/NounsSeederV2.sol";
import {LilNounsUnitTest} from "./helpers/LilNounsUnitTest.sol";

contract LilVRGDAV2Test is LilNounsUnitTest {
    int256 targetPrice = int256(0.15e18);
    int256 priceDecayPercent = 0.31e18;
    int256 perUnitTime = 24 * 4 * 1e18;
    uint256 startTime = block.timestamp;
    uint256 reservePrice = 0;

    // WIP, not functional yet
    function testUpgradeToV2() public {
        // Deploy v1 LilVRGDA
        deploy(
            targetPrice,
            priceDecayPercent,
            perUnitTime,
            startTime,
            reservePrice
        );
        populateDescriptor();
        vm.roll(1000); // Set block.number

        // Deploy V2 Seeder
        NounsSeederV2 seederV2 = new NounsSeederV2(address(nounsToken));

        // Set NounsToken to use V2 Seeder
        nounsToken.setSeeder(seederV2);

        // Deploy V2 LilVRGDA
        LilVRGDAV2 vrgdaV2 = new LilVRGDAV2();
        vrgdaV2.initialize(
            targetPrice,
            priceDecayPercent,
            perUnitTime,
            startTime,
            address(nounsToken),
            address(weth),
            reservePrice
        );
        nounsToken.setMinter(address(vrgdaV2));
        vrgdaV2.transferOwnership(nounsDAOAddress);

        // Update V2 Seeder Interval
        seederV2.setUpdateInterval(5);

        // Test settleAuction with V2 LilVRGDA
        for (uint256 i = 0; i < 10; i++) {
            (uint256 nounId, , , uint256  price, bytes32 hash) = vrgdaV2.fetchNextNoun();
            vm.roll(block.number + 1); // Set block.number
            // Should be able to supply an out of date hash so long as it within the interval
            vrgdaV2.settleAuction{value: price}(nounId,  hash);
        }
    }
}
