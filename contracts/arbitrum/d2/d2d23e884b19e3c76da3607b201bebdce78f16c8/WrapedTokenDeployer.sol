// SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6;

import "./IWrapedTokenDeployer.sol";
import "./WrapedToken.sol";

contract WrapedTokenDeployer is IWrapedTokenDeployer {
    struct Parameters {
        uint256 origin;
        bytes origin_hash;
        uint8 origin_decimals;
    }

    /// @inheritdoc IWrapedTokenDeployer
    Parameters public override parameters;

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @param name token name
    /// @param symbol token symbol
    /// @param origin chain ID
    /// @param origin_hash hash in origin chain
    function _deploy(
        string memory name,
        string memory symbol,
        uint256 origin,
        bytes memory origin_hash,
        uint8 origin_decimals
    ) internal returns (address token) {
        parameters = Parameters({origin: origin, origin_hash: origin_hash, origin_decimals: origin_decimals});
        token = address(new WrapedToken{salt: keccak256(abi.encode(origin, origin_hash, origin_decimals))}(name, symbol));
        delete parameters;
    }
}
