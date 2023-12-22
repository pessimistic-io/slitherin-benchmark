// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./Rescuable.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./IUniV3Dex.sol";

import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract UniV3DexModule is UUPSUpgradeable, OwnableUpgradeable, Rescuable, IUniV3Dex {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint256 public constant DEADLINE_DELTA = 10;
    uint256 public constant AMOUNT_OUT_MIN = 0;

    address constant COMP = 0x354A6dA3fcde098F8389cad84b0182725c6C91dE;
    address constant STG = 0x6694340fc020c5E6B96567843da2df01b2CE1eb6;
    address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /// @dev Reserved storage space to allow for layout changes in the future
    uint256[50] private ______gap;

    mapping(address => mapping(address => address[])) public routes;

    /**
    * @notice  Disable initializing on implementation contract
    **/
    constructor() {
        _disableInitializers();
    }

    /** proxy **/

    /**
    * @notice  Initialize Uniswap V3 swap module
    * @param   _routes  Token swap routes for Uniswap
    */
    function initialize(
        address[][] memory _routes
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();

        setRoutes(_routes);
    }

    /**
   * @notice  Makes sure only the owner can upgrade, called from upgradeTo(..)
   * @param   newImplementation Contract address of newImplementation
   */
    function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyOwner
    {}

    /**
     * @notice  Get current implementation contract
     * @return  address  Returns current implement contract
     */
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }


    /**
     * @notice  Swap between two ERC20 tokens
     * @param   _amountIn  Token amount in
     * @param   _in  Token address In
     * @param   _out  Token address Out
     * @param   _to  Address of the receiver of amounts
     * @return  amounts  Amounts of token out
     */
    function swap(uint256 _amountIn, address _in, address _out, address _to) external returns (uint amounts) {
        //if (swapPreview(_amountIn, _in, _out) > 0) {
        if (_amountIn != 0) {
            IERC20Upgradeable(_in).safeTransferFrom(msg.sender, address(this), _amountIn);

            if (_in == COMP) {
                bytes memory path = abi.encodePacked(
                    COMP,
                    uint24(3000),
                    WETH,
                    uint24(500),
                    USDC
                );

                uint amountOut = swapExactInputMultiHop(path, _in, _amountIn, _to);
                return amountOut;
            }

            if (_in == STG) {
                bytes memory path = abi.encodePacked(
                    STG,
                    uint24(3000),
                    WETH,
                    uint24(500),
                    USDC
                );

                return swapExactInputMultiHop(path, _in, _amountIn, _to);
            }
            return 0;
        }
        return 0;
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint amountIn,
        address to
    ) internal returns (uint amountOut) {

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
        .ExactInputSingleParams({
        tokenIn : tokenIn,
        tokenOut : tokenOut,
        fee : poolFee,
        recipient : to,
        deadline : block.timestamp,
        amountIn : amountIn,
        amountOutMinimum : AMOUNT_OUT_MIN,
        sqrtPriceLimitX96 : 0
        });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function swapExactInputMultiHop(
        bytes memory path,
        address tokenIn,
        uint amountIn,
        address to
    ) internal returns (uint amountOut) {
        IERC20Upgradeable(tokenIn).approve(address(swapRouter), amountIn);
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
        path : path,
        recipient : to,
        deadline : block.timestamp,
        amountIn : amountIn,
        amountOutMinimum : 0
        });
        amountOut = swapRouter.exactInput(params);
    }

    /**
     * @notice  Add new route or update existing route
     * @param   _routes  Routes to add or to update
     */
    function setRoutes(address[][] memory _routes) public onlyOwner {
        for (uint8 i = 0; i < _routes.length; i++) {
            routes[_routes[i][0]][_routes[i][_routes[i].length - 1]] = _routes[i];
            uint256 allowance = IERC20(_routes[i][0]).allowance(address(this), address(swapRouter));
            if (allowance == 0) {
                IERC20Upgradeable(_routes[i][0]).safeApprove(address(swapRouter), type(uint256).max);
            }
        }
    }

    /**
     * @notice  Delete routes
     * @param   _routes  Routes to delete
     */
    function deleteRoutes(address[][] memory _routes) external onlyOwner {
        for (uint8 i = 0; i < _routes.length; i++) {
            delete routes[_routes[i][0]][_routes[i][_routes[i].length - 1]];
        }
    }

    /**
     * @notice  Get swap route for a given pair
     * @param   _in  Token address In
     * @param   _out  Token address Out
     * @return  route  Swap route for a given pair
     */
    function getRoute(address _in, address _out) external view returns (address[] memory route) {
        return routes[_in][_out];
    }

    /**
    * @notice  Rescue a stuck ERC20 token
    */
    function rescueToken(address token) external onlyOwner {
        _rescueToken(token);
    }

    /**
    * @notice  Rescue native tokens
    */
    function rescueNative() external onlyOwner {
        _rescueNative();
    }
}

