// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./TransferHelper.sol";
import "./ClearingHouse.sol";
import "./OwnableUpgradeableSafe.sol";

contract Liquidator is OwnableUpgradeableSafe {
    using TransferHelper for IERC20;

    ClearingHouse clearingHouse;

    event PositionLiquidated(address amm, address[] traders, bool[] results, string[] reasons);

    function initialize(ClearingHouse _clearingHouse) public initializer {
        __Ownable_init();
        clearingHouse = _clearingHouse;
    }

    receive() external payable {}

    function setClearingHouse(address _addrCH) external onlyOwner {
        clearingHouse = ClearingHouse(_addrCH);
    }

    function withdrawERC20(IERC20 _token) external onlyOwner {
        _token.safeTransfer(msg.sender, _token.balanceOf(address(this)));
    }

    function withdrawETH() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }(new bytes(0));
        require(success, "L_ETF"); //eth transfer failed
    }

    function singleLiquidate(IAmm _amm, address _trader) external {
        clearingHouse.liquidate(_amm, _trader);
    }

    function liquidate(IAmm _amm, address[] memory _traders) external {
        uint256 len = _traders.length;
        bool[] memory results = new bool[](len);
        string[] memory reasons = new string[](len);
        uint256 i;
        for (i; i < len; ) {
            // (success, ret) = clearingHouse.call(abi.encodeWithSelector(IClearingHouse.liquidate.selector, _amm, _traders[i]));
            try clearingHouse.liquidate(_amm, _traders[i]) {
                results[i] = true;
            } catch Error(string memory reason) {
                reasons[i] = reason;
            } catch {
                reasons[i] = "";
            }
            unchecked {
                i++;
            }
        }
        emit PositionLiquidated(address(_amm), _traders, results, reasons);
    }

    function isLiquidatable(IAmm _amm, address[] memory _traders) external view returns (bool[] memory) {
        uint256 mmRatio = _amm.maintenanceMarginRatio();
        bool[] memory results = new bool[](_traders.length);
        for (uint256 i = 0; i < _traders.length; i++) {
            try clearingHouse.getMarginRatio(_amm, _traders[i]) returns (int256 ratio) {
                if (ratio < int256(mmRatio)) {
                    results[i] = true;
                } else {
                    results[i] = false;
                }
            } catch Error(string memory) {
                results[i] = false;
            } catch {
                results[i] = false;
            }
        }
        return results;
    }
}

