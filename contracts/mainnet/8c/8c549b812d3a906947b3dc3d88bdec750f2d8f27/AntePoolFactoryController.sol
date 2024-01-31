// SPDX-License-Identifier: GPL-3.0-only

// ┏━━━┓━━━━━┏┓━━━━━━━━━┏━━━┓━━━━━━━━━━━━━━━━━━━━━━━
// ┃┏━┓┃━━━━┏┛┗┓━━━━━━━━┃┏━━┛━━━━━━━━━━━━━━━━━━━━━━━
// ┃┗━┛┃┏━┓━┗┓┏┛┏━━┓━━━━┃┗━━┓┏┓┏━┓━┏━━┓━┏━┓━┏━━┓┏━━┓
// ┃┏━┓┃┃┏┓┓━┃┃━┃┏┓┃━━━━┃┏━━┛┣┫┃┏┓┓┗━┓┃━┃┏┓┓┃┏━┛┃┏┓┃
// ┃┃ ┃┃┃┃┃┃━┃┗┓┃┃━┫━┏┓━┃┃━━━┃┃┃┃┃┃┃┗┛┗┓┃┃┃┃┃┗━┓┃┃━┫
// ┗┛ ┗┛┗┛┗┛━┗━┛┗━━┛━┗┛━┗┛━━━┗┛┗┛┗┛┗━━━┛┗┛┗┛┗━━┛┗━━┛
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pragma solidity ^0.8.0;

import "./EnumerableSet.sol";
import "./Ownable.sol";
import "./IAntePoolFactoryController.sol";

/// @title Ante V0.6 Ante Pool Factory Controller smart contract
/// @notice Contract that handles the whitelisted ERC20 tokens
contract AntePoolFactoryController is IAntePoolFactoryController, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev A set of unique ERC20 token addresses that are allowed
    /// to be used by the factory.
    EnumerableSet.AddressSet private allowedTokens;

    /// @dev The minimum stake amount for each allowed token
    mapping(address => uint256) public tokenMinimums;

    /// @inheritdoc IAntePoolFactoryController
    address public override antePoolLogicAddr;

    /// @inheritdoc IAntePoolFactoryController
    function addToken(address _tokenAddr, uint256 _min) external override onlyOwner {
        _addToken(_tokenAddr, _min);
    }

    /// @inheritdoc IAntePoolFactoryController
    function addTokens(address[] memory _tokenAddresses, uint256[] memory _mins) external override onlyOwner {
        require(_tokenAddresses.length == _mins.length, "ANTE: Minimum is not set");

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            address tokenAddr = _tokenAddresses[i];
            uint256 tokenMin = _mins[i];
            _addToken(tokenAddr, tokenMin);
        }
    }

    /// @inheritdoc IAntePoolFactoryController
    function removeToken(address _tokenAddr) external override onlyOwner {
        bool success = allowedTokens.remove(_tokenAddr);
        require(success, "ANTE: Token does not exist");
        emit TokenRemoved(_tokenAddr);
    }

    /// @inheritdoc IAntePoolFactoryController
    function setTokenMinimum(address _tokenAddr, uint256 _min) external override onlyOwner {
        require(_min > 0, "ANTE: Minimum must be greater than 0");
        require(allowedTokens.contains(_tokenAddr), "ANTE: Token not supported");
        tokenMinimums[_tokenAddr] = _min;
        emit TokenMinimumUpdated(_tokenAddr, _min);
    }

    /// @inheritdoc IAntePoolFactoryController
    function setPoolLogicAddr(address _antePoolLogicAddr) external override onlyOwner {
        require(_antePoolLogicAddr != address(0), "ANTE: Invalid address");
        address oldLogicAddr = antePoolLogicAddr;
        antePoolLogicAddr = _antePoolLogicAddr;
        emit AntePoolImplementationUpdated(oldLogicAddr, _antePoolLogicAddr);
    }

    /// @inheritdoc IAntePoolFactoryController
    function isTokenAllowed(address _tokenAddr) external view override returns (bool) {
        return allowedTokens.contains(_tokenAddr);
    }

    /// @inheritdoc IAntePoolFactoryController
    function getTokenMinimum(address _tokenAddr) external view returns (uint256) {
        require(allowedTokens.contains(_tokenAddr), "ANTE: Token not supported");

        return tokenMinimums[_tokenAddr];
    }

    /// @inheritdoc IAntePoolFactoryController
    function getAllowedTokens() external view override returns (address[] memory) {
        address[] memory allowedTokenAddresses = new address[](allowedTokens.length());

        for (uint256 i = 0; i < allowedTokens.length(); i++) {
            allowedTokenAddresses[i] = allowedTokens.at(i);
        }

        return allowedTokenAddresses;
    }

    /*****************************************************
     * =============== INTERNAL HELPERS ================ *
     *****************************************************/

    function _addToken(address _tokenAddr, uint256 _min) internal {
        require(_min > 0, "ANTE: Minimum must be greater than 0");
        bool success = allowedTokens.add(_tokenAddr);
        require(success, "ANTE: Token already exists");
        tokenMinimums[_tokenAddr] = _min;
        emit TokenAdded(_tokenAddr, _min);
    }
}

