// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {ERC20} from "./ERC20.sol";
import {ERC20Permit} from "./ERC20Permit.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Ownable2Step} from "./Ownable2Step.sol";

import {IWETH9} from "./IWETH9.sol";
import {IAToken} from "./IAToken.sol";
import {IPool} from "./IPool.sol";
import {DataTypes} from "./DataTypes.sol";
import {ReserveConfiguration} from "./ReserveConfiguration.sol";
import {IAaveTokenSubstitute} from "./IAaveTokenSubstitute.sol";
import {WadRayMath} from "./WadRayMath.sol";

contract AaveTokenSubstitute is IAaveTokenSubstitute, ERC20Permit, Ownable2Step {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    uint256 public constant SUPPLY_BUFFER = 10 ** 24; // 0.1%

    IWETH9 private immutable _weth;
    IPool private immutable _aaveV3Pool;
    uint8 private immutable _decimals;
    address public immutable override aToken;
    address public immutable override underlyingToken;

    address public override treasury;

    constructor(address weth_, address asset_, address aaveV3Pool_, address treasury_, address owner_)
        ERC20Permit(string.concat("Wrapped Aave ", IERC20Metadata(asset_).name()))
        ERC20(
            string.concat("Wrapped Aave ", IERC20Metadata(asset_).name()),
            string.concat("Wa", IERC20Metadata(asset_).symbol())
        )
    {
        _weth = IWETH9(weth_);
        _aaveV3Pool = IPool(aaveV3Pool_);
        aToken = _aaveV3Pool.getReserveData(asset_).aTokenAddress;
        _decimals = IERC20Metadata(asset_).decimals();
        underlyingToken = asset_;
        _transferOwnership(owner_);
        treasury = treasury_;
        emit SetTreasury(treasury_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mintByAToken(uint256 amount, address to) external {
        IERC20(aToken).safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function mint(uint256 amount, address to) external {
        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 supplyAmount = IERC20(underlyingToken).balanceOf(address(this));
        DataTypes.ReserveConfigurationMap memory configuration =
            _aaveV3Pool.getReserveData(underlyingToken).configuration;

        DataTypes.ReserveData memory reserveData = _aaveV3Pool.getReserveData(underlyingToken);
        uint256 supplyCap = configuration.getSupplyCap();
        if (supplyCap == 0) {
            supplyCap = type(uint256).max;
        } else {
            uint256 existingSupply = (IAToken(aToken).scaledTotalSupply() + uint256(reserveData.accruedToTreasury))
                .rayMul(reserveData.liquidityIndex + SUPPLY_BUFFER);
            supplyCap *= 10 ** IERC20Metadata(underlyingToken).decimals();
            unchecked {
                supplyCap = supplyCap <= existingSupply ? 0 : supplyCap - existingSupply;
            }
        }

        _mint(to, amount);
        if (!configuration.getActive() || configuration.getPaused()) {
            return;
        } else if (supplyAmount > supplyCap) {
            supplyAmount = supplyCap;
        }
        IERC20(underlyingToken).approve(address(_aaveV3Pool), supplyAmount);
        try _aaveV3Pool.supply(underlyingToken, supplyAmount, address(this), 0) {} catch {}
    }

    function mintableAmount() external pure returns (uint256) {
        return type(uint256).max;
    }

    function burnToAToken(uint256 amount, address to) external {
        _burn(msg.sender, amount);
        IERC20(aToken).safeTransfer(address(to), amount);
    }

    function burn(uint256 amount, address to) external {
        unchecked {
            _burn(msg.sender, amount);

            uint256 underlyingAmount = IERC20(underlyingToken).balanceOf(address(this));
            DataTypes.ReserveConfigurationMap memory configuration =
                _aaveV3Pool.getReserveData(underlyingToken).configuration;

            if (amount <= underlyingAmount) {
                underlyingAmount = amount;
            } else if (configuration.getActive() && !configuration.getPaused()) {
                uint256 withdrawableAmount = IERC20(underlyingToken).balanceOf(aToken);
                if (withdrawableAmount + underlyingAmount < amount) {
                    if (withdrawableAmount > 0) {
                        _aaveV3Pool.withdraw(underlyingToken, withdrawableAmount, address(this));
                        underlyingAmount += withdrawableAmount;
                    }
                } else {
                    _aaveV3Pool.withdraw(underlyingToken, amount - underlyingAmount, address(this));
                    underlyingAmount = amount;
                }
            }

            if (underlyingAmount > 0) {
                if (underlyingToken == address(_weth)) {
                    _weth.withdraw(underlyingAmount);
                    (bool success,) = payable(to).call{value: amount}("");
                    if (!success) revert ValueTransferFailed();
                } else {
                    IERC20(underlyingToken).safeTransfer(address(to), underlyingAmount);
                }
                amount -= underlyingAmount;
            }

            if (amount > 0) {
                IERC20(aToken).safeTransfer(address(to), amount);
            }
        }
    }

    function burnableAmount() external pure returns (uint256) {
        return type(uint256).max;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
        emit SetTreasury(newTreasury);
    }

    function claim() external {
        uint256 adminYield = IERC20(aToken).balanceOf(address(this)) - totalSupply() - 1;
        if (adminYield > 0) {
            IERC20(aToken).safeTransfer(treasury, adminYield);
            emit Claim(treasury, adminYield);
        }
    }

    function withdrawLostToken(address token, address recipient) external onlyOwner {
        if (token == aToken || token == underlyingToken) {
            revert InvalidToken();
        }
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(recipient, balance);
        }
    }

    receive() external payable {}
}

