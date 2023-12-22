// SPDX-License-Identifier: GPL-3.0
/*                            ******@@@@@@@@@**@*                               
                        ***@@@@@@@@@@@@@@@@@@@@@@**                             
                     *@@@@@@**@@@@@@@@@@@@@@@@@*@@@*                            
                  *@@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@*@**                          
                 *@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@*                         
                **@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@**                       
                **@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@@@@@*                      
                **@@@@@@@@@@@@@@@@*************************                    
                **@@@@@@@@***********************************                   
                 *@@@***********************&@@@@@@@@@@@@@@@****,    ******@@@@*
           *********************@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@************* 
      ***@@@@@@@@@@@@@@@*****@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@****@@*********      
   **@@@@@**********************@@@@*****************#@@@@**********            
  *@@******************************************************                     
 *@************************************                                         
 @*******************************                                               
 *@*************************                                                    
   ********************* 
   
    /$$$$$                                               /$$$$$$$   /$$$$$$   /$$$$$$ 
   |__  $$                                              | $$__  $$ /$$__  $$ /$$__  $$
      | $$  /$$$$$$  /$$$$$$$   /$$$$$$   /$$$$$$$      | $$  \ $$| $$  \ $$| $$  \ $$
      | $$ /$$__  $$| $$__  $$ /$$__  $$ /$$_____/      | $$  | $$| $$$$$$$$| $$  | $$
 /$$  | $$| $$  \ $$| $$  \ $$| $$$$$$$$|  $$$$$$       | $$  | $$| $$__  $$| $$  | $$
| $$  | $$| $$  | $$| $$  | $$| $$_____/ \____  $$      | $$  | $$| $$  | $$| $$  | $$
|  $$$$$$/|  $$$$$$/| $$  | $$|  $$$$$$$ /$$$$$$$/      | $$$$$$$/| $$  | $$|  $$$$$$/
 \______/  \______/ |__/  |__/ \_______/|_______/       |_______/ |__/  |__/ \______/                                      
*/

pragma solidity ^0.8.10;

// Interfaces
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IGMXRouter} from "./IGMXRouter.sol";
import {IGMXVault} from "./IGMXVault.sol";
import {IGMXOrderBook} from "./IGMXOrderBook.sol";
import {IGMXPositionManager} from "./IGMXPositionManager.sol";

library GmxAdapter {
    using SafeERC20 for IERC20;

    /// GMX Router contract
    IGMXRouter public constant GMXRouter = IGMXRouter(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);

    /// GMX Vault contract
    IGMXVault public constant GMXVault = IGMXVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);

    /// GMX Position Manager used to execute GMX strategies.
    IGMXPositionManager public constant GMXPositionManager =
        IGMXPositionManager(0x75E42e6f01baf1D6022bEa862A28774a9f8a4A0C);

    IGMXOrderBook public constant GMXOrderBook = IGMXOrderBook(0x09f77E8A13De9a35a7231028187e9fD5DB8a2ACB);

    address public constant wETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function swapTokens(address _source, address _destination, uint256 _amountIn, uint256 _amountOutMin) external {
        IERC20(_source).safeApprove(address(GMXRouter), _amountIn);
        address[] memory path = new address[](2);
        path[0] = _source;
        path[1] = _destination;
        GMXRouter.swap(path, _amountIn, _amountOutMin, address(this));
        IERC20(_source).safeApprove(address(GMXRouter), 0);
    }

    function increasePosition(
        address _tokenIn,
        address _collateralToken,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        uint256 _price,
        bool _isLong
    )
        external
        returns (bool)
    {
        if (_isLong && _collateralToken != _indexToken) {
            revert COLLATERAL_TOKEN_NOT_EQUAL_TO_INDEX();
        }

        // approve allowance for router
        IERC20(_tokenIn).safeApprove(address(GMXRouter), _amountIn);

        address[] memory path;
        if (_tokenIn == _collateralToken) {
            path = new address[](1);
            path[0] = _tokenIn;
        } else {
            path = new address[](2);
            path[0] = _tokenIn;
            path[1] = _collateralToken;
        }

        GMXPositionManager.increasePosition(
            path,
            _indexToken, // the address of the token to long
            _amountIn, // the amount of tokenIn to deposit as collateral
            _minOut, // the min amount of collateralToken to swap for
            _sizeDelta, // the USD value of the change in position size
            _isLong, // is long
            _price // the USD value of the index price accepted when opening the position
        );

        IERC20(_tokenIn).safeApprove(address(GMXRouter), 0);

        emit IncreasePosition(_tokenIn, _collateralToken, _indexToken, _amountIn, _minOut, _sizeDelta, _isLong, _price);
        return true;
    }

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _price,
        bool _isLong,
        address _receiver
    )
        external
        returns (bool)
    {
        if (_isLong && _collateralToken != _indexToken) {
            revert COLLATERAL_TOKEN_NOT_EQUAL_TO_INDEX();
        }

        GMXPositionManager.decreasePosition(
            _collateralToken, // the collateral token used
            _indexToken, //  the index token of the position
            _collateralDelta, // the amount of collateral in USD value to withdraw
            _sizeDelta, // the USD value of the change in position size
            _isLong, // is long
            _receiver, // the address to receive the withdrawn tokens
            _price // the USD value of the max index price accepted when decreasing the position
        );

        emit DecreasePosition(_collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _price);
        return true;
    }

    function createIncreaseOrder(
        address _tokenIn,
        address _purchaseToken,
        uint256 _amountIn,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        address _collateralToken,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    )
        external
        returns (bool)
    {
        uint256 executionFee = GMXOrderBook.minExecutionFee();
        if (msg.value < executionFee) {
            revert INVALID_EXECUTION_FEE();
        }

        address[] memory path;
        if (_tokenIn == _purchaseToken) {
            path = new address[](1);
            path[0] = _purchaseToken;
        } else {
            path = new address[](2);
            path[0] = _tokenIn;
            path[1] = _purchaseToken;
        }

        IERC20(_tokenIn).safeApprove(address(GMXRouter), _amountIn);

        GMXOrderBook.createIncreaseOrder{value: msg.value}(
            path,
            _amountIn,
            _indexToken,
            _minOut,
            _sizeDelta,
            _collateralToken,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            executionFee,
            false
        );

        IERC20(_tokenIn).safeApprove(address(GMXRouter), 0);

        return true;
    }

    function createDecreaseOrder(
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    )
        external
        returns (bool)
    {
        uint256 executionFee = GMXOrderBook.minExecutionFee();
        if (msg.value <= executionFee) {
            revert INVALID_EXECUTION_FEE();
        }

        GMXOrderBook.createDecreaseOrder{value: msg.value}(
            _indexToken, _sizeDelta, _collateralToken, _collateralDelta, _isLong, _triggerPrice, _triggerAboveThreshold
        );

        return true;
    }

    function cancelOrder(bool _isIncreaseOrder, uint256 _orderIndex) external {
        if (_isIncreaseOrder) {
            GMXOrderBook.cancelIncreaseOrder(_orderIndex);
        } else {
            GMXOrderBook.cancelDecreaseOrder(_orderIndex);
        }
    }

    /**
     * Emitted when a GMX position is increased
     *
     * @param _tokenIn The address of token to deposit that will be swapped for `_collateralToken`. Enter the same address as `_collateralToken` if token swap isn't necessary.
     * @param _collateralToken the address of the collateral token. For longs, it must be the same as the `_indexToken`
     * @param _indexToken the address of the token to long
     * @param _amountIn the amount of tokenIn to deposit as collateral
     * @param _minOut the min amount of collateralToken to swap for
     * @param _sizeDelta the USD value of the change in position size
     * @param _isLong is long
     * @param _price the USD value of index price accepted when opening the position
     */
    event IncreasePosition(
        address indexed _tokenIn,
        address indexed _collateralToken,
        address indexed _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    );

    /**
     * Emitted when a GMX position is increased
     *
     * @param _collateralToken the collateral token used
     * @param _indexToken  the index token of the position
     * @param _collateralDelta the amount of collateral in USD value to withdraw
     * @param _isLong indicates if position was long
     * @param _price price in usd (scaled to 30) of the index token to decrease position
     */
    event DecreasePosition(
        address indexed _collateralToken,
        address indexed _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    );

    error COLLATERAL_TOKEN_NOT_EQUAL_TO_INDEX();
    error INVALID_EXECUTION_FEE();
}

