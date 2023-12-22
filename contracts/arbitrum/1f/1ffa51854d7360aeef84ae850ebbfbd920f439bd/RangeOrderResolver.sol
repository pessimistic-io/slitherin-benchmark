// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import {IEjectResolver} from "./IEjectResolver.sol";
import {IEjectLP} from "./IEjectLP.sol";
import {Order} from "./SEject.sol";

contract RangeOrderResolver is IEjectResolver {
    IEjectLP public immutable ejectLP;

    constructor(IEjectLP ejectLP_) {
        ejectLP = ejectLP_;
    }

    function checker(
        uint256 tokenId_,
        Order memory order_,
        address feeToken_
    ) external view override returns (bool, bytes memory data) {
        try ejectLP.canEject(tokenId_, order_, feeToken_) {
            return (
                true,
                abi.encodeWithSelector(
                    IEjectLP.eject.selector,
                    tokenId_,
                    order_
                )
            );
        } catch {
            return (
                false,
                abi.encode(
                    IEjectLP.eject.selector,
                    tokenId_,
                    order_
                )
            );
        }
    }
}

