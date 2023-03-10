// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {LilVRGDA} from "../../src/LilVRGDA.sol";
import {IProxyRegistry} from "lil-nouns-contracts/external/opensea/IProxyRegistry.sol";
import {NounsDescriptor} from "lil-nouns-contracts/NounsDescriptor.sol";
import {NounsAuctionHouse} from "lil-nouns-contracts/NounsAuctionHouse.sol";
import {NounsSeeder} from "lil-nouns-contracts/NounsSeeder.sol";
import {INounsSeeder} from "lil-nouns-contracts/interfaces/INounsSeeder.sol";
import {NounsToken} from "lil-nouns-contracts/NounsToken.sol";
import {WETH} from "lil-nouns-contracts/test/WETH.sol";

// LilNounsUnitTest is the base class that unit test contracts inherit from
contract LilNounsUnitTest is Test {
    IProxyRegistry proxyRegistry;
    NounsToken nounsToken;
    INounsSeeder seeder;
    LilVRGDA vrgda;
    NounsDescriptor descriptor;
    NounsAuctionHouse oldAuctionHouse;
    WETH weth;

    address noundersDAOAddress = address(1); // Used by NounsToken
    address nounsDAOAddress = address(2); // nounsDAOAddress is set as owner of LilVRGDA

    /* Utils */

    // Taken from nouns-monorepo
    function readFile(
        string memory filepath
    ) internal returns (bytes memory output) {
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = filepath;
        output = vm.ffi(inputs);
    }

    function deploy(
        int256 _targetPrice,
        int256 _priceDecayPercent,
        int256 _perTimeUnit,
        uint256 _startTime,
        uint256 _reservePrice
    ) public {
        weth = new WETH();

        // Set up the existing Nouns contracts
        oldAuctionHouse = new NounsAuctionHouse();
        address proxyRegistryAddress = address(11);
        proxyRegistry = IProxyRegistry(proxyRegistryAddress);
        descriptor = new NounsDescriptor();
        seeder = new NounsSeeder();
        nounsToken = new NounsToken(
            noundersDAOAddress,
            nounsDAOAddress,
            address(oldAuctionHouse),
            descriptor,
            seeder,
            proxyRegistry
        );
        oldAuctionHouse.initialize(
            nounsToken, // nounsToken
            address(weth), // weth
            1 minutes, // timeBuffer
            _reservePrice, // reservePrice
            1, // minBidIncrementPercent
            15 minutes // duration
        );
        vrgda = new LilVRGDA();
        vrgda.initialize(
            _targetPrice,
            _priceDecayPercent,
            _perTimeUnit,
            _startTime,
            address(nounsToken)
        );
        vrgda.transferOwnership(nounsDAOAddress);
        nounsToken.setMinter(address(vrgda));
        vm.prank(nounsDAOAddress);
        vrgda.unpause();

        // Weth address should have transferred over
        assertEq(vrgda.weth(), oldAuctionHouse.weth());

        // Reserve price should have transferred over
        assertEq(vrgda.reservePrice(), oldAuctionHouse.reservePrice());

        // NounID should have transferred over
        (uint256 nounId, , , , , ) = oldAuctionHouse.auction();
        if (nounId != 0) {
            assertEq(vrgda.nextNounId(), nounId + 1);
        } else {
            assertEq(vrgda.nextNounId(), nounId);
        }
    }

    // This function is taken from
    // https://github.com/nounsDAO/nouns-monorepo/blob/0c15de7071e1b95b6a542396d345a53b19f86e22/packages/nouns-contracts/test/foundry/helpers/DescriptorHelpers.sol#L14
    function populateDescriptor() public {
        // created with `npx hardhat descriptor-v1-export-abi`
        string memory filename = "./test/files/descriptor_v1/image-data.abi";
        bytes memory content = readFile(filename);
        (
            string[] memory bgcolors,
            string[] memory palette,
            bytes[] memory bodies,
            bytes[] memory accessories,
            bytes[] memory heads,
            bytes[] memory glasses
        ) = abi.decode(
                content,
                (string[], string[], bytes[], bytes[], bytes[], bytes[])
            );

        descriptor.addManyBackgrounds(bgcolors);
        descriptor.addManyColorsToPalette(0, palette);
        descriptor.addManyBodies(bodies);
        descriptor.addManyAccessories(accessories);
        descriptor.addManyHeads(heads);
        descriptor.addManyGlasses(glasses);
    }
}
