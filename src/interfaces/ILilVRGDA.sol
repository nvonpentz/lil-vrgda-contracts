pragma solidity ^0.8.17;

import { INounsSeeder } from "lil-nouns-contracts/interfaces/INounsSeeder.sol";

interface ILilVRGDA {
    event AuctionSettled(uint256 indexed nounId, address winner, uint256 amount);
    event AuctionReservePriceUpdated(uint256 reservePrice);
    event AuctionUpdateIntervalUpdated(uint256 updateInterval);

    function settleAuction(uint256 nounId, bytes32 expectedParentBlockhash) external payable;
    function fetchNextNoun() external view returns (
        uint nounId,
        INounsSeeder.Seed memory seed,
        string memory svg,
        uint256 price,
        bytes32 hash
    );
    function pause() external;
    function unpause() external;
    function setReservePrice(uint256 reservePrice) external;
}
