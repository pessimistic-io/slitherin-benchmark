// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IFeeConverterV1.sol";

contract FeeConverterV1 is 
    IFeeConverterV1,
    Initializable, 
    UUPSUpgradeable,
    AccessControlUpgradeable 
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    // V1
    ISwapRouter public swapRouter;
    IEtherealSpheresPool public etherealSpheresPool;
    IERC20Upgradeable public weth;

    EnumerableSetUpgradeable.AddressSet private _tokens;

    mapping(address => bytes) public pathByToken;

    /// @inheritdoc IFeeConverterV1
    function initialize(
        ISwapRouter swapRouter_,
        IEtherealSpheresPool etherealSpheresPool_,
        IERC20Upgradeable weth_
    ) 
        external 
        initializer 
    {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        swapRouter = swapRouter_;
        etherealSpheresPool = etherealSpheresPool_;
        weth = weth_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc IFeeConverterV1
    function updatePathForToken(
        address token_, 
        address[] calldata path_,
        uint24[] calldata fees_
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (path_.length != fees_.length || path_.length == 0) {
            revert InvalidArrayLengths();
        }
        if (!_tokens.contains(token_)) {
            _tokens.add(token_);
            emit TokenAdded(token_);
        }
        bytes memory path = abi.encodePacked(token_);
        for (uint256 i = 0; i < path_.length; i++) {
            path = abi.encodePacked(path, fees_[i], path_[i]);
        }
        pathByToken[token_] = path;
        emit PathUpdated(token_, path);
    }

    /// @inheritdoc IFeeConverterV1
    function removeToken(address token_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _tokens.remove(token_);
        delete pathByToken[token_];
        emit TokenRemoved(token_);
    }

    /// @inheritdoc IFeeConverterV1
    function convert() external {
        uint256 length = _tokens.length();
        ISwapRouter m_swapRouter = swapRouter;
        for (uint256 i = 0; i < length; ) {
            address token = _tokens.at(i);
            uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
            if (balance > 0) {
                ISwapRouter.ExactInputParams memory params =
                    ISwapRouter.ExactInputParams({
                        path: pathByToken[token],
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: balance,
                        amountOutMinimum: 0
                    });
                m_swapRouter.exactInput(params);
            }
            unchecked {
                i++;
            }
        }
        IERC20Upgradeable m_weth = weth;
        uint256 reward = m_weth.balanceOf(address(this));
        IEtherealSpheresPool m_etherealSpheresPool = etherealSpheresPool;
        m_weth.safeTransfer(address(m_etherealSpheresPool), reward);
        m_etherealSpheresPool.provideReward(reward);
        emit ConversionCompleted(reward);
    }

    /// @inheritdoc IFeeConverterV1
    function numberOfTokens() external view returns (uint256) {
        return _tokens.length();
    }

    /// @inheritdoc IFeeConverterV1
    function getTokenAt(uint256 index_) external view returns (address) {
        return _tokens.at(index_);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
