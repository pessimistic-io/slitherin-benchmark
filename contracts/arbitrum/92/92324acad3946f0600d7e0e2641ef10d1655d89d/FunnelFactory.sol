// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IFunnelFactory } from "./IFunnelFactory.sol";
import { IERC5827Proxy } from "./IERC5827Proxy.sol";
import { IFunnelErrors } from "./IFunnelErrors.sol";
import { Funnel } from "./Funnel.sol";
import { Clones } from "./Clones.sol";

/// @title Factory for all the funnel contracts
/// @author Zac (zlace0x), zhongfu (zhongfu), Edison (edison0xyz)
contract FunnelFactory is IFunnelFactory, IFunnelErrors {
    using Clones for address;

    /// Stores the mapping between tokenAddress => funnelAddress
    mapping(address => address) deployments;

    /// address of the implementation. This is immutable due to security as implementation is not
    /// supposed to change after deployment
    address public immutable funnelImplementation;

    /// @notice Deploys the FunnelFactory contract
    /// @dev requires a valid funnelImplementation address
    /// @param _funnelImplementation The address of the implementation
    constructor(address _funnelImplementation) {
        if (_funnelImplementation == address(0)) {
            revert InvalidAddress({ _input: _funnelImplementation });
        }
        funnelImplementation = _funnelImplementation;
    }

    /// @inheritdoc IFunnelFactory
    function deployFunnelForToken(address _tokenAddress) external returns (address _funnelAddress) {
        if (deployments[_tokenAddress] != address(0)) {
            revert FunnelAlreadyDeployed();
        }

        if (_tokenAddress.code.length == 0) {
            revert InvalidToken();
        }

        _funnelAddress = funnelImplementation.cloneDeterministic(bytes32(uint256(uint160(_tokenAddress))));

        deployments[_tokenAddress] = _funnelAddress;
        Funnel(_funnelAddress).initialize(_tokenAddress);
        emit DeployedFunnel(_tokenAddress, _funnelAddress);
    }

    /// @inheritdoc IFunnelFactory
    function getFunnelForToken(address _tokenAddress) public view returns (address _funnelAddress) {
        if (deployments[_tokenAddress] == address(0)) {
            revert FunnelNotDeployed();
        }

        return deployments[_tokenAddress];
    }

    /// @inheritdoc IFunnelFactory
    function isFunnel(address _funnelAddress) external view returns (bool) {
        // Not a deployed contract
        if (_funnelAddress.code.length == 0) {
            return false;
        }

        try IERC5827Proxy(_funnelAddress).baseToken() returns (address baseToken) {
            if (baseToken == address(0)) {
                return false;
            }
            return _funnelAddress == getFunnelForToken(baseToken);
        } catch {
            return false;
        }
    }
}

