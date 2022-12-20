// SPDX-License-Identifier: GPL-3.0

/// @title The V2 NounsToken pseudo-random seed generator

/*********************************
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░██░░░████░░██░░░████░░░ *
 * ░░██████░░░████████░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 *********************************/

pragma solidity ^0.8.17;

import {INounsSeederV2} from "./interfaces/INounsSeederV2.sol";
import {INounsDescriptor} from "lil-nouns-contracts/interfaces/INounsDescriptor.sol";
import {NounsToken} from "lil-nouns-contracts/NounsToken.sol";

// Same as NounsSeederV1 except it can has a configurable updateInterval variable
// determining how long a noun updates
contract NounsSeederV2 is INounsSeederV2 {
    NounsToken nounsToken;
    uint32 internal updateInterval = 1;

    // Constructor sets the NounsToken from the address
    constructor(address _nounsTokenAddress) {
        nounsToken = NounsToken(_nounsTokenAddress);
    }

    /**
     * @notice Generate a pseudo-random Noun seed using the previous blockhash and noun ID.
     */
    function generateSeed(
        uint256 nounId,
        INounsDescriptor descriptor
    ) external view override returns (Seed memory) {
        // Calculate pseudo-random seed using the previous blockhash and noun ID considering the update interval
        uint256 pseudorandomness = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(roundToNearest(block.number, updateInterval) - 1),
                    nounId
                )
            )
        );

        uint256 backgroundCount = descriptor.backgroundCount();
        uint256 bodyCount = descriptor.bodyCount();
        uint256 accessoryCount = descriptor.accessoryCount();
        uint256 headCount = descriptor.headCount();
        uint256 glassesCount = descriptor.glassesCount();

        return
            Seed({
                background: uint48(uint48(pseudorandomness) % backgroundCount),
                body: uint48(uint48(pseudorandomness >> 48) % bodyCount),
                accessory: uint48(
                    uint48(pseudorandomness >> 96) % accessoryCount
                ),
                head: uint48(uint48(pseudorandomness >> 144) % headCount),
                glasses: uint48(uint48(pseudorandomness >> 192) % glassesCount)
            });
    }

    function setUpdateInterval(uint32 _updateInterval) external {
        require(
            msg.sender == nounsToken.owner(),
            "Caller is not the owner of nouns token"
        );
        require(_updateInterval > 0, "Update interval must be greater than 0");
        updateInterval = _updateInterval;

        emit UpdateIntervalUpdated(_updateInterval);
    }

    // @notice Get the update interval for the nouns token
    function getUpdateInterval() external view returns (uint32) {
        return updateInterval;
    }

    // @notice Calculate the nearest block number less than or equal to the given block number
    // that is a multiple of the update interval
    function roundToNearest(
        uint256 blockNumber,
        uint32 interval
    ) internal pure returns (uint256) {
        return blockNumber - (blockNumber % interval);
    }
}
