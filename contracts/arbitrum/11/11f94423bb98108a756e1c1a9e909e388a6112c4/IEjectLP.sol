// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.7;

import {     INonfungiblePositionManager } from "./INonfungiblePositionManager.sol";
import {IPokeMe} from "./IPokeMe.sol";
import {Order, OrderParams} from "./SEject.sol";

interface IEjectLP {
    function cancel(uint256 tokenId_, Order memory order_) external;

    function schedule(OrderParams memory orderParams_) external;

    function eject(uint256 tokenId_, Order memory order_) external;

    function pokeMe() external view returns (IPokeMe);

    function nftPositions() external view returns (INonfungiblePositionManager);

    function canEject(
        uint256 tokenId_,
        Order memory order_,
        address feeToken_
    )
        external
        view
        returns (
            address,
            address,
            uint128
        );
}

