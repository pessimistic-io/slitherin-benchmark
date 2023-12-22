// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

import "./Governable.sol";
import "./IController.sol";
import "./IRewardForwarder.sol";
import "./IProfitSharingReceiver.sol";
import "./IStrategy.sol";
import "./IUniversalLiquidatorV1.sol";
import "./Controllable.sol";

/**
 * @dev This contract receives rewards from strategies and is responsible for routing the reward's liquidation into
 *      specific buyback tokens and profit tokens for the DAO.
 */
contract RewardForwarder is Controllable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    constructor(
        address _storage
    ) public Controllable(_storage) {}

    function notifyFee(
        address _token,
        uint256 _profitSharingFee,
        uint256 _strategistFee,
        uint256 _platformFee
    ) external {
        _notifyFee(
            _token,
            _profitSharingFee,
            _strategistFee,
            _platformFee
        );
    }

    function _notifyFee(
        address _token,
        uint256 _profitSharingFee,
        uint256 _strategistFee,
        uint256 _platformFee
    ) internal {
        address _controller = controller();
        address liquidator = IController(_controller).universalLiquidator();

        uint totalTransferAmount = _profitSharingFee.add(_strategistFee).add(_platformFee);
        require(totalTransferAmount > 0, "totalTransferAmount should not be 0");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), totalTransferAmount);

        address _targetToken = IController(_controller).targetToken();

        if (_targetToken != _token) {
            IERC20(_token).safeApprove(liquidator, 0);
            IERC20(_token).safeApprove(liquidator, totalTransferAmount);

            uint amountOutMin = 1;

            if (_strategistFee > 0) {
                IUniversalLiquidatorV1(liquidator).swapTokens(
                    _token,
                    _targetToken,
                    _strategistFee,
                    amountOutMin,
                    IStrategy(msg.sender).strategist()
                );
            }
            if (_platformFee > 0) {
                IUniversalLiquidatorV1(liquidator).swapTokens(
                    _token,
                    _targetToken,
                    _platformFee,
                    amountOutMin,
                    IController(_controller).governance()
                );
            }
            if (_profitSharingFee > 0) {
                IUniversalLiquidatorV1(liquidator).swapTokens(
                    _token,
                    _targetToken,
                    _profitSharingFee,
                    amountOutMin,
                    IController(_controller).profitSharingReceiver()
                );
            }
        } else {
            IERC20(_targetToken).safeTransfer(IStrategy(msg.sender).strategist(), _strategistFee);
            IERC20(_targetToken).safeTransfer(IController(_controller).governance(), _platformFee);
            IERC20(_targetToken).safeTransfer(IController(_controller).profitSharingReceiver(), _profitSharingFee);
        }
    }
}

