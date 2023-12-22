/**
 * SPDX-License-Identifier: Proprietary
 * 
 * Strateg Protocol contract
 * PROPRIETARY SOFTWARE AND LICENSE. 
 * This contract is the valuable and proprietary property of Strateg Development Association. 
 * Strateg Development Association shall retain exclusive title to this property, and all modifications, 
 * implementations, derivative works, upgrades, productizations and subsequent releases. 
 * To the extent that developers in any way contributes to the further development of Strateg protocol contracts, 
 * developers hereby irrevocably assign and/or agrees to assign all rights in any such contributions or further developments to Strateg Development Association. 
 * Without limitation, Strateg Development Association acknowledges and agrees that all patent rights, 
 * copyrights in and to the Strateg protocol contracts shall remain the exclusive property of Strateg Development Association at all times.
 * 
 * DEVELOPERS SHALL NOT, IN WHOLE OR IN PART, AT ANY TIME: 
 * (i) SELL, ASSIGN, LEASE, DISTRIBUTE, OR OTHER WISE TRANSFER THE STRATEG PROTOCOL CONTRACTS TO ANY THIRD PARTY; 
 * (ii) COPY OR REPRODUCE THE STRATEG PROTOCOL CONTRACTS IN ANY MANNER;
 */
pragma solidity 0.8.7;

import "./SafeERC20.sol";
import "./Ownable.sol";

import "./Flags.sol";
import "./IDeBridgeGateExtended.sol";

import {IStrategXGateway} from "./IStrategXGateway.sol";
import {IStrategVault} from "./IStrategVault.sol";
import {ICurvePool} from "./ICurvePool.sol";
import {ICurvePoolToken} from "./ICurvePoolToken.sol";

contract StrategDebridgeXGateway is Ownable, IStrategXGateway {
    using SafeERC20 for IERC20;

    struct GatewayParams {
        uint256 targetedChainId;
        uint256 executionFee;
        uint256 minAmountOut;
    }

    IDeBridgeGateExtended public deBridgeGate;
    IERC20 public _3CRVToken;
    ICurvePool public _3CRV;
    ICurvePool public deUsdcCurvePool;
    IERC20 public deUSDC;

    event XTransfer(uint32 dstChainId, address dstVault, uint256 dstAmount);
    event XReceive(
        address _receiver,
        address _vault,
        address _asset,
        uint256 _amount
    );

    uint32 private immutable REFERAL_CODE = 4540;
    bool public CURVE_UNDERLYING;
    uint256 public META_POOL_TOKEN_COUNT;



    constructor(
        IDeBridgeGateExtended _deBridgeGate,
        ICurvePool _deUsdcCurvePool
    ) {
        deBridgeGate = _deBridgeGate;
        deUsdcCurvePool = _deUsdcCurvePool;
        deUSDC = IERC20(deUsdcCurvePool.coins(0));

        address lptoken = deUsdcCurvePool.coins(1);

        address pool;
        try ICurvePoolToken(lptoken).minter() returns (address _lp) {
            pool = _lp;
        } catch {
            pool = lptoken;
        }

        _3CRVToken = IERC20(lptoken);
        _3CRV = ICurvePool(pool);

        try _3CRV.underlying_coins(0) returns (address) {
            CURVE_UNDERLYING = true;
        } catch {
            CURVE_UNDERLYING = false;
        }

        try _3CRV.coins(2) returns (address) {
            META_POOL_TOKEN_COUNT = 3;
        } catch {
            META_POOL_TOKEN_COUNT = 2;
        }
    }

    fallback() external payable {}
    receive() external payable {}

    function _swapDeUSDC(bool _in) internal {
        if(_in){
            uint256 bal = _3CRVToken.balanceOf(address(this));
            _3CRVToken.approve(address(deUsdcCurvePool),bal );
            deUsdcCurvePool.exchange(1, 0, bal, 0);
        } else {
            uint256 bal = deUSDC.balanceOf(address(this));
            deUSDC.approve(address(deUsdcCurvePool), bal);
            deUsdcCurvePool.exchange(0, 1, bal, 0);
        }
    }

    function _change3CRV(bool _in, address _token) internal {
        uint256 coinsIdx;
        
        for (uint256 i = 0; i < META_POOL_TOKEN_COUNT; i++) {
            address underlyingCoin;
            if(CURVE_UNDERLYING){
                underlyingCoin = _3CRV.underlying_coins(i);
            } else {
                underlyingCoin = _3CRV.coins(i);
            }
                
            
            if(underlyingCoin == _token) {
                coinsIdx = i;
            }
        }
        if(_in) {
            uint256[] memory uamounts = new uint256[](META_POOL_TOKEN_COUNT);
            uamounts[coinsIdx] = IERC20(_token).balanceOf(address(this));
            IERC20(_token).approve(address(_3CRV), uamounts[coinsIdx]);
            if(CURVE_UNDERLYING) {
                _3CRV.add_liquidity(uamounts, 0, true);
            } else {
                _3CRV.add_liquidity(uamounts, 0);
            }
        } else {
            uint256 amount = _3CRVToken.balanceOf(address(this));
            _3CRVToken.approve(address(_3CRV), amount);
            if(CURVE_UNDERLYING) {
                _3CRV.remove_liquidity_one_coin(amount, int128(uint128(coinsIdx)), 0, true);
            } else {
                _3CRV.remove_liquidity_one_coin(amount, int128(uint128(coinsIdx)), 0);
            }
        }
    }

    function migrateToXChainVault(
        address _fromAsset,
        uint256 _fromAmount,
        address _gatewayTargeted,
        address _vaultTargeted,
        bytes calldata _xGatewayParams
    ) external payable override {
        GatewayParams memory params = abi.decode(
            _xGatewayParams,
            (GatewayParams)
        );

        IERC20(_fromAsset).transferFrom(msg.sender, address(this), _fromAmount);

        _change3CRV(true, _fromAsset);
        _swapDeUSDC(true);

        uint256 deUSDCBal = deUSDC.balanceOf(address(this));
        deUSDC.approve(address(deBridgeGate), deUSDCBal);


        //
        // sanity checks
        //
        uint256 protocolFee = deBridgeGate.globalFixedNativeFee();
        require(
            msg.value >= (protocolFee + params.executionFee),
            "fees not covered by the msg.value"
        );

        // we bridge as much asset as specified in the executionFee arg
        // (i.e. bridging the minimum necessary amount to to cover the cost of execution)
        // However, deBridge cuts a small fee off the bridged asset, so
        // we must ensure that executionFee < amountToBridge
        uint assetFeeBps = deBridgeGate.globalTransferFeeBps();
        uint amountAfterBridge = (params.executionFee * (10000 - assetFeeBps)) /
            10000;

        require(amountAfterBridge > params.minAmountOut, "!minAmountOut");

        //
        // start configuring a message
        //
        IDeBridgeGate.SubmissionAutoParamsTo memory autoParams;

        // use the whole amountAfterBridge as the execution fee to be paid to the executor
        autoParams.executionFee = amountAfterBridge;

        // if something happens, we need to revert the transaction, otherwise the sender will loose assets
        autoParams.flags = Flags.setFlag(
            autoParams.flags,
            Flags.REVERT_IF_EXTERNAL_FAIL,
            true
        );

        autoParams.data = abi.encodeWithSelector(
            bytes4(keccak256("xReceive(address,address,uint256)")),
            tx.origin,
            _vaultTargeted,
            params.minAmountOut
        );

        autoParams.fallbackAddress = abi.encodePacked(msg.sender);

        deBridgeGate.send{value: msg.value}(
            address(deUSDC), // _tokenAddress
            deUSDCBal, // _amount
            params.targetedChainId, // _chainIdTo
            abi.encodePacked(_gatewayTargeted), // _receiver
            "", // _permit
            false, // _useAssetFee
            REFERAL_CODE, // _referralCode
            abi.encode(autoParams) // _autoParams
        );

        payable(tx.origin).call{value: address(this).balance};
    }

    /**
     * @notice The receiver function as required by the IXReceiver interface.
     * @dev The Connext bridge contract will call this function.
     */
    function xReceive(
        address _receiver,
        address _vault,
        uint256 _amount
    ) external {
        address asset = IStrategVault(_vault).asset();
        _receiveXChainMigration(_receiver, _vault, asset);
        emit XReceive(_receiver, asset, _vault, _amount);
    }

    function _receiveXChainMigration(
        address _receiver,
        address _vaultTargeted,
        address _asset
    ) internal {
        deUSDC.safeTransferFrom(
            msg.sender,
            address(this),
            deUSDC.balanceOf(msg.sender)
        );

        _swapDeUSDC(false);
        _change3CRV(false, _asset);
        
        uint256 assetBal = IERC20(_asset).balanceOf(address(this));
        IERC20(_asset).approve(_vaultTargeted, assetBal);
        IStrategVault(_vaultTargeted).deposit(assetBal, _receiver);
    }

    function rescue(address _token) external onlyOwner {
        IERC20(_token).transfer(
            msg.sender,
            IERC20(_token).balanceOf(address(this))
        );
    }

}

