// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./Ownable.sol";

import "./IStargateRouter.sol";
import "./ILendingPool.sol";

/*
    Chain Ids
        Ethereum: 1
        BSC: 2
        Avalanche: 6
        Polygon: 9
        Arbitrum: 10
        Optimism: 11
        Fantom: 12

    Pool Ids
        Ethereum
            USDC: 1
            USDT: 2
        BSC
            USDT: 2
            BUSD: 5
        Avalanche
            USDC: 1
            USDT: 2
        Polygon
            USDC: 1
            USDT: 2
        Arbitrum
            USDC: 1
            USDT: 2
        Optimism
            USDC: 1
        Fantom
            USDC: 1
 */

contract StargateBorrow is Ownable {
    using SafeMath for uint256;

    /// @notice Stargate Router
    IStargateRouter public router;

    /// @notice Lending Pool address
    ILendingPool public lendingPool;

    /// @notice asset => poolId; at the moment, pool IDs for USDC and USDT are the same accross all chains
    mapping(address => uint256) public poolIdPerChain;

    constructor(
        IStargateRouter _router,
        ILendingPool _lendingPool
    ) {
        router = _router;
        lendingPool = _lendingPool;
    }
    
    // Set pool ids of assets
    function setPoolIDs(address[] memory assets, uint256[] memory poolIDs) external onlyOwner {
        for (uint256 i = 0; i < assets.length; i += 1) {
            poolIdPerChain[assets[i]] = poolIDs[i];
        }
    }

    // Call Router.sol method to get the value for swap()
    function quoteLayerZeroSwapFee(
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        IStargateRouter.lzTxObj memory _lzTxParams
    ) external view returns (uint256, uint256) {
        return router.quoteLayerZeroFee(
            _dstChainId,
            _functionType,
            _toAddress,
            _transferAndCallPayload,
            _lzTxParams
        );
    }

    /**
     * @dev Loop the deposit and borrow of an asset
     * @param asset for loop
     * @param amount for the initial deposit
     * @param interestRateMode stable or variable borrow mode
     * @param dstChainId Destination chain id
     **/
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 dstChainId
    ) external payable {
        lendingPool.borrow(asset, amount, interestRateMode, 0, msg.sender);
        IERC20(asset).approve(address(router), amount);
        router.swap{value: msg.value}(
            dstChainId, // dest chain id
            poolIdPerChain[asset], // src chain pool id
            poolIdPerChain[asset], // dst chain pool id
            msg.sender, // receive address
            amount, // transfer amount
            amount.mul(99).div(100), // max slippage: 1%
            IStargateRouter.lzTxObj(0, 0, "0x"),
            abi.encodePacked(msg.sender),
            bytes("")
        );
    }
}
