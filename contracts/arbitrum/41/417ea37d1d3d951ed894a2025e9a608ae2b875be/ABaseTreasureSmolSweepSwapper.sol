// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

//           _____                    _____                   _______                   _____            _____                    _____                    _____                    _____
//          /\    \                  /\    \                 /::\    \                 /\    \          /\    \                  /\    \                  /\    \                  /\    \
//         /::\    \                /::\____\               /::::\    \               /::\____\        /::\    \                /::\____\                /::\    \                /::\    \
//        /::::\    \              /::::|   |              /::::::\    \             /:::/    /       /::::\    \              /:::/    /               /::::\    \              /::::\    \
//       /::::::\    \            /:::::|   |             /::::::::\    \           /:::/    /       /::::::\    \            /:::/   _/___            /::::::\    \            /::::::\    \
//      /:::/\:::\    \          /::::::|   |            /:::/~~\:::\    \         /:::/    /       /:::/\:::\    \          /:::/   /\    \          /:::/\:::\    \          /:::/\:::\    \
//     /:::/__\:::\    \        /:::/|::|   |           /:::/    \:::\    \       /:::/    /       /:::/__\:::\    \        /:::/   /::\____\        /:::/__\:::\    \        /:::/__\:::\    \
//     \:::\   \:::\    \      /:::/ |::|   |          /:::/    / \:::\    \     /:::/    /        \:::\   \:::\    \      /:::/   /:::/    /       /::::\   \:::\    \      /::::\   \:::\    \
//   ___\:::\   \:::\    \    /:::/  |::|___|______   /:::/____/   \:::\____\   /:::/    /       ___\:::\   \:::\    \    /:::/   /:::/   _/___    /::::::\   \:::\    \    /::::::\   \:::\    \
//  /\   \:::\   \:::\    \  /:::/   |::::::::\    \ |:::|    |     |:::|    | /:::/    /       /\   \:::\   \:::\    \  /:::/___/:::/   /\    \  /:::/\:::\   \:::\    \  /:::/\:::\   \:::\____\
// /::\   \:::\   \:::\____\/:::/    |:::::::::\____\|:::|____|     |:::|    |/:::/____/       /::\   \:::\   \:::\____\|:::|   /:::/   /::\____\/:::/  \:::\   \:::\____\/:::/  \:::\   \:::|    |
// \:::\   \:::\   \::/    /\::/    / ~~~~~/:::/    / \:::\    \   /:::/    / \:::\    \       \:::\   \:::\   \::/    /|:::|__/:::/   /:::/    /\::/    \:::\  /:::/    /\::/    \:::\  /:::|____|
//  \:::\   \:::\   \/____/  \/____/      /:::/    /   \:::\    \ /:::/    /   \:::\    \       \:::\   \:::\   \/____/  \:::\/:::/   /:::/    /  \/____/ \:::\/:::/    /  \/_____/\:::\/:::/    /
//   \:::\   \:::\    \                  /:::/    /     \:::\    /:::/    /     \:::\    \       \:::\   \:::\    \       \::::::/   /:::/    /            \::::::/    /            \::::::/    /
//    \:::\   \:::\____\                /:::/    /       \:::\__/:::/    /       \:::\    \       \:::\   \:::\____\       \::::/___/:::/    /              \::::/    /              \::::/    /
//     \:::\  /:::/    /               /:::/    /         \::::::::/    /         \:::\    \       \:::\  /:::/    /        \:::\__/:::/    /               /:::/    /                \::/____/
//      \:::\/:::/    /               /:::/    /           \::::::/    /           \:::\    \       \:::\/:::/    /          \::::::::/    /               /:::/    /                  ~~
//       \::::::/    /               /:::/    /             \::::/    /             \:::\    \       \::::::/    /            \::::::/    /               /:::/    /
//        \::::/    /               /:::/    /               \::/____/               \:::\____\       \::::/    /              \::::/    /               /:::/    /
//         \::/    /                \::/    /                 ~~                      \::/    /        \::/    /                \::/____/                \::/    /
//          \/____/                  \/____/                                           \/____/          \/____/                  ~~                       \/____/

import "./Ownable.sol";
import "./introspection_IERC165.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./ERC165.sol";
import "./ReentrancyGuard.sol";

import "./ANFTReceiver.sol";
import "./SettingsBitFlag.sol";
import "./Math.sol";
import "./ITreasureMarketplace.sol";

import "./ABaseTreasureSmolSweeper.sol";
import "./ABaseSwapper.sol";
import "./ITreasureSmolSweepSwapper.sol";

import "./ArrayUtils.sol";

abstract contract ABaseTreasureSmolSweepSwapper is
    ITreasureSmolSweepSwapper,
    ABaseTreasureSmolSweeper,
    ABaseSwapper
{
    using SafeERC20 for IERC20;
    using SettingsBitFlag for uint16;
    using MemoryArrayUtilsForAddress for address[];

    constructor(
        address _treasureMarketplace,
        address _defaultPaymentToken,
        IUniswapV2Router02[] memory _swapRouters
    )
        ABaseTreasureSmolSweeper(_treasureMarketplace, _defaultPaymentToken)
        ABaseSwapper(_swapRouters)
    {}

    // here the max ETH spend is msg.value. assume msg.value will be all spent
    function buyUsingETH(
        BuyOrder[] calldata _buyOrders,
        uint16 _inputSettingsBitFlag,
        address[] calldata _path,
        uint32 _routerId,
        uint256 _deadline
    ) external payable nonReentrant {
        IUniswapV2Router02 router = swapRouters[_routerId];
        uint256[] memory amountsIn = router.swapExactETHForTokens{
            value: msg.value
        }(0, _path, address(this), _deadline);
        uint256 maxSpendIncFees = amountsIn[amountsIn.length - 1];

        (
            uint256 totalSpentAmount,
            uint256 successCount
        ) = _buyUsingPaymentToken(
                _buyOrders,
                _inputSettingsBitFlag,
                _calculateAmountWithoutFees(maxSpendIncFees)
            );

        // transfer back failed payment tokens to the buyer
        if (successCount == 0) revert AllReverted();

        uint256 feeAmount = _calculateFee(totalSpentAmount);
        uint256 refundAmount = maxSpendIncFees - (totalSpentAmount + feeAmount);
        if (
            _inputSettingsBitFlag.checkSetting(
                SettingsBitFlag.REFUND_IN_INPUT_TOKEN
            )
        ) {
            address[] memory reversePath = _path.reverse();
            IERC20(defaultPaymentToken).approve(address(router), refundAmount);
            uint256[] memory amounts = router.swapExactTokensForETH(
                refundAmount,
                0,
                reversePath,
                address(this),
                _deadline
            );
            payable(msg.sender).transfer(amounts[amounts.length - 1]);
        } else {
            defaultPaymentToken.safeTransfer(msg.sender, refundAmount);
        }
    }

    function buyUsingOtherToken(
        BuyOrder[] calldata _buyOrders,
        uint16 _inputSettingsBitFlag,
        uint256 _maxInputTokenAmount,
        address[] calldata _path,
        uint32 _routerId,
        uint256 _deadline
    ) external nonReentrant {
        IUniswapV2Router02 router = swapRouters[_routerId];
        IERC20(_path[0]).approve(address(router), _maxInputTokenAmount);
        uint256[] memory amountsIn = router.swapExactTokensForTokens(
            _maxInputTokenAmount,
            0,
            _path,
            address(this),
            _deadline
        );
        uint256 maxSpendIncFees = amountsIn[amountsIn.length - 1];

        (
            uint256 totalSpentAmount,
            uint256 successCount
        ) = _buyUsingPaymentToken(
                _buyOrders,
                _inputSettingsBitFlag,
                _calculateAmountWithoutFees(maxSpendIncFees)
            );

        // transfer back failed payment tokens to the buyer
        if (successCount == 0) revert AllReverted();

        uint256 feeAmount = _calculateFee(totalSpentAmount);
        uint256 refundAmount = maxSpendIncFees - (totalSpentAmount + feeAmount);
        if (
            _inputSettingsBitFlag.checkSetting(
                SettingsBitFlag.REFUND_IN_INPUT_TOKEN
            )
        ) {
            address[] memory reversePath = _path.reverse();
            IERC20(defaultPaymentToken).approve(address(router), refundAmount);
            uint256[] memory amounts = router.swapExactTokensForTokens(
                refundAmount,
                0,
                reversePath,
                address(this),
                _deadline
            );
            payable(msg.sender).transfer(amounts[amounts.length - 1]);
        } else {
            defaultPaymentToken.safeTransfer(
                msg.sender,
                maxSpendIncFees - (totalSpentAmount + feeAmount)
            );
        }
    }

    function sweepUsingETH(
        BuyOrder[] calldata _buyOrders,
        uint16 _inputSettingsBitFlag,
        uint32 _maxSuccesses,
        uint32 _maxFailures,
        uint256 _minSpend,
        address[] calldata _path,
        uint32 _routerId,
        uint256 _deadline
    ) external payable nonReentrant {
        IUniswapV2Router02 router = swapRouters[_routerId];
        uint256 maxSpendIncFees;
        {
            uint256[] memory amountsIn = router.swapExactETHForTokens{
                value: msg.value
            }(0, _path, address(this), _deadline);
            maxSpendIncFees = amountsIn[amountsIn.length - 1];
        }

        (
            uint256 totalSpentAmount,
            uint256 successCount
        ) = _sweepUsingPaymentToken(
                _buyOrders,
                _inputSettingsBitFlag,
                _maxSuccesses,
                _maxFailures,
                _calculateAmountWithoutFees(maxSpendIncFees),
                _minSpend
            );

        // transfer back failed payment tokens to the buyer
        if (successCount == 0) revert AllReverted();

        uint256 feeAmount = _calculateFee(totalSpentAmount);
        uint256 refundAmount = maxSpendIncFees - (totalSpentAmount + feeAmount);
        if (
            _inputSettingsBitFlag.checkSetting(
                SettingsBitFlag.REFUND_IN_INPUT_TOKEN
            )
        ) {
            address[] memory reversePath = _path.reverse();
            IERC20(defaultPaymentToken).approve(address(router), refundAmount);
            uint256[] memory amounts = router.swapExactTokensForETH(
                refundAmount,
                0,
                reversePath,
                address(this),
                _deadline
            );
            payable(msg.sender).transfer(amounts[amounts.length - 1]);
        } else {
            defaultPaymentToken.safeTransfer(
                msg.sender,
                maxSpendIncFees - (totalSpentAmount + feeAmount)
            );
        }
    }

    function sweepUsingOtherToken(
        BuyOrder[] calldata _buyOrders,
        uint16 _inputSettingsBitFlag,
        uint32 _maxSuccesses,
        uint32 _maxFailures,
        uint256 _maxInputTokenAmount,
        uint256 _minSpend,
        address[] calldata _path,
        uint32 _routerId,
        uint256 _deadline
    ) external nonReentrant {
        IUniswapV2Router02 router = swapRouters[_routerId];
        uint256 maxSpendIncFees;
        {
            IERC20(_path[0]).approve(address(router), _maxInputTokenAmount);
            uint256[] memory amountsIn = router.swapExactTokensForTokens(
                _maxInputTokenAmount,
                0,
                _path,
                address(this),
                _deadline
            );
            maxSpendIncFees = amountsIn[amountsIn.length - 1];
        }
        (
            uint256 totalSpentAmount,
            uint256 successCount
        ) = _sweepUsingPaymentToken(
                _buyOrders,
                _inputSettingsBitFlag,
                _maxSuccesses,
                _maxFailures,
                _calculateAmountWithoutFees(maxSpendIncFees),
                _minSpend
            );

        // transfer back failed payment tokens to the buyer
        if (successCount == 0) revert AllReverted();

        if (
            _inputSettingsBitFlag.checkSetting(
                SettingsBitFlag.REFUND_IN_INPUT_TOKEN
            )
        ) {
            uint256 refundAmount = maxSpendIncFees -
                (totalSpentAmount + _calculateFee(totalSpentAmount));
            address[] memory reversePath = _path.reverse();
            IERC20(defaultPaymentToken).approve(address(router), refundAmount);
            uint256[] memory amounts = router.swapExactTokensForTokens(
                refundAmount,
                0,
                reversePath,
                address(this),
                _deadline
            );
            payable(msg.sender).transfer(amounts[amounts.length - 1]);
        } else {
            defaultPaymentToken.safeTransfer(
                msg.sender,
                maxSpendIncFees -
                    (totalSpentAmount + _calculateFee(totalSpentAmount))
            );
        }
    }
}

