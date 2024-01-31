// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { PriceOracle } from "./PriceOracle.sol";
import { CToken } from "./CToken.sol";
import { Errors } from "./src_Errors.sol";

// Internal references
import { Trust } from "./Trust.sol";
import { Token } from "./Token.sol";
import { FixedMath } from "./FixedMath.sol";
import { BaseAdapter as Adapter } from "./BaseAdapter.sol";

contract TargetOracle is PriceOracle, Trust {
    using FixedMath for uint256;

    /// @notice target address -> adapter address
    mapping(address => address) public adapters;

    constructor() Trust(msg.sender) {}

    function setTarget(address target, address adapter) external requiresTrust {
        adapters[target] = adapter;
    }

    function getUnderlyingPrice(CToken cToken) external view override returns (uint256) {
        // For the sense Fuse pool, the underlying will be the Target. The semantics here can be a little confusing
        // as we now have two layers of underlying, cToken -> Target (cToken's underlying) -> Target's underlying
        Token target = Token(cToken.underlying());
        return _price(address(target));
    }

    function price(address target) external view override returns (uint256) {
        return _price(target);
    }

    function _price(address target) internal view returns (uint256) {
        address adapter = adapters[address(target)];
        if (adapter == address(0)) revert Errors.AdapterNotSet();

        // Use the cached scale for view function compatibility
        uint256 scale = Adapter(adapter).scaleStored();

        // `Target / Target's underlying` * `Target's underlying / ETH` = `Price of Target in ETH`
        //
        // `scale` and the value returned by `getUnderlyingPrice` are expected to be WADs
        return scale.fmul(Adapter(adapter).getUnderlyingPrice());
    }
}

