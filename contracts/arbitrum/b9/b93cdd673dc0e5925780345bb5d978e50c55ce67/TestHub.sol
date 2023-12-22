// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./Ownable.sol";
import "./IERC20Upgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./ITestHub.sol";
import "./TestDataTypes.sol";

contract TestHub is Ownable, ITestHub {
    address public constant WETH_ADDRESS =
        0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public aAddress;

    // function initialize() public initializer {
    //     __Ownable_init();
    // }

    constructor(address _aAddress) {
        aAddress = _aAddress;
        // __Ownable_init();
    }

    function setAddresses(address _aAddress) external override onlyOwner {
        aAddress = _aAddress;
    }

    /**
     *
     *
     * @param _swapParams (amountOut, dexType, dexAddress, router)
     *   struct SwapParams {
     *      bytes params;
     *      bytes data;
     *   }
     * SwapParams.params defines dexType/dexAddr
     * dexType: 1inch==1, uniswapx==2
     * dexAddr: 1inch==V5 aggregation contract
     *
     * `swapParams` must set compatibility = true, the contract always execute
     * swap(IAggregationExecutor executor,
     *      SwapDescription calldata desc,
     *      bytes calldata permit,
     *      bytes calldata data)
     * returns(uint256 returnAmount, uint256 spentAmount)
     */
    function swap(
        address _collateral,
        uint256 _amountIn,
        TestDataTypes.SwapParams calldata _swapParams
    ) external override returns (uint256) {
        //transfer collateral to this contract

        uint256 beforeWethAmount = IERC20Upgradeable(WETH_ADDRESS).balanceOf(
            address(this)
        );

        (uint256 dexType, address dexAddr) = abi.decode(
            _swapParams.params,
            (uint256, address)
        );
        uint256 returnAmount; //weth amount
        if (dexType == 1) {
            //1inch
            (bool success, bytes memory data) = dexAddr.call(_swapParams.data);
            require(success, "swap by 1inch failed");
            (returnAmount, ) = abi.decode(data, (uint256, uint256));
        } else if (dexType == 2) {
            //uniswapx
            //TODO
        }

        //judge whether the quantity is correct
        uint256 afterWethAmount = IERC20Upgradeable(WETH_ADDRESS).balanceOf(
            address(this)
        );
        // require(
        //     returnAmount == afterWethAmount - beforeWethAmount,
        //     "swap return amount error"
        // );
        //send weth to ActivePool
        // SafeERC20Upgradeable.safeTransfer(
        //     IERC20Upgradeable(WETH_ADDRESS),
        //     aAddress,
        //     returnAmount
        // );

        emit Swap(_collateral, beforeWethAmount, afterWethAmount, returnAmount);
        return returnAmount;
    }

    event Swap(
        address _collateral,
        uint beforeWethAmount,
        uint afterWethAmount,
        uint returnAmount
    );

    function judgeSlippage(
        uint256 _slippage,
        uint256 _wethPrice,
        address _collateral,
        uint256 _collateralPrice,
        uint _amountIn,
        uint returnAmount
    ) public view returns(bool) {
        uint256 actualWETHValue = (_wethPrice * returnAmount) /
            10 ** ERC20Upgradeable(WETH_ADDRESS).decimals();
        uint256 collValue = (_collateralPrice * _amountIn) /
            10 ** ERC20Upgradeable(_collateral).decimals();
        bool b = false;

        if(actualWETHValue >= collValue ||
                ((collValue - actualWETHValue) * 1 ether) / collValue <=
                _slippage) {
                    b = true;
        } else {
            b = false;
        }
        return b;
    }

    // approve all collaterals
    function approve(address _collateral, address _spender) public onlyOwner {
        IERC20Upgradeable(_collateral).approve(_spender, type(uint256).max);
    }

    function transfer(address _collateral, address _to, uint _amount) public {
        SafeERC20Upgradeable.safeTransfer(
            IERC20Upgradeable(_collateral),
            _to,
            _amount
        );
    }

}

