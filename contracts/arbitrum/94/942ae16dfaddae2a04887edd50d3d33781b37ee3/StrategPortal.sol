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

pragma solidity ^0.8.15;

import "./Ownable.sol";
import "./IERC20.sol";
import {IStrategVault} from "./IStrategVault.sol";
import {IStrategXGateway} from "./IStrategXGateway.sol";
import {IStrategSwapRouter} from "./IStrategSwapRouter.sol";

contract StrategPortal is Ownable {

    struct PermitParams {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    mapping(address => bool) public gatewayAllowed;
    mapping(address => bool) public routerAllowed;

    event FundTransfer(address indexed addr, string name, string symbol, address asset, address indexed owner);
    event XFundTransfer(address indexed addr, string name, string symbol, address asset, address indexed owner);
   

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    constructor(
    ) {
    }

    function setAllowedGateway(address _address, bool enabled)
        external
        onlyOwner
    {
        gatewayAllowed[_address] = enabled;
    }

    function setAllowedRouter(address _address, bool enabled)
        external
        onlyOwner
    {
        gatewayAllowed[_address] = enabled;
    }

    function xFundTransfer(
        address _vaultSource,
        uint256 _vaultSourceSharesAmount,
        address _targetAsset,

        address _factoryTargeted,
        address _vaultTargeted,

        address _xSwapAddress,
        bytes calldata _xSwapParams,

        address _xGatewayAddress,
        bytes calldata _xGatewayParams
    ) external payable {
        _xFundTransfer(
            _vaultSource,
            _vaultSourceSharesAmount,
            _targetAsset,
            _factoryTargeted,
            _vaultTargeted,
            _xSwapAddress,
            _xSwapParams,
            _xGatewayAddress,
            _xGatewayParams
        );
    }

    function xFundTransferWithPermit(
        address _vaultSource,
        uint256 _vaultSourceSharesAmount,
        address _targetAsset,

        address _factoryTargeted,
        address _vaultTargeted,

        address _xSwapAddress,
        bytes calldata _xSwapParams,

        address _xGatewayAddress,
        bytes calldata _xGatewayParams,

        bytes memory _permitParams
    ) external payable {
        PermitParams memory p = abi.decode(_permitParams, (PermitParams));
        _permit(
            _vaultSource,
            p.deadline,
            _vaultSourceSharesAmount,
            p.v,
            p.r,
            p.s
        );
        _xFundTransfer(
            _vaultSource,
            _vaultSourceSharesAmount,
            _targetAsset,
            _factoryTargeted,
            _vaultTargeted,
            _xSwapAddress,
            _xSwapParams,
            _xGatewayAddress,
            _xGatewayParams
        );
    }

    function fundTransfer(
        address _vaultSource,
        uint256 _vaultSourceSharesAmount,
        address _vaultTargeted,
        address _xSwapAddress,
        bytes calldata _xSwapParams
    ) external {
        _fundTransfer(
            _vaultSource,
            _vaultSourceSharesAmount,
            _vaultTargeted,
            _xSwapAddress,
            _xSwapParams
        );
    }

    function fundTransferWithPermit(
        address _vaultSource,
        uint256 _vaultSourceSharesAmount,
        address _vaultTargeted,
        bytes memory _permitParams,
        address _xSwapAddress,
        bytes calldata _xSwapParams
    ) external {
        PermitParams memory p = abi.decode(_permitParams, (PermitParams));
        _permit(
            _vaultSource,
            p.deadline,
            _vaultSourceSharesAmount,
            p.v,
            p.r,
            p.s
        );
        _fundTransfer(
            _vaultSource,
            _vaultSourceSharesAmount,
            _vaultTargeted,
            _xSwapAddress,
            _xSwapParams
        );
    }

    function _permit(
        address _vaultSource,
        uint256 _deadline,
        uint256 _vaultSourceSharesAmount,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal {
        IStrategVault(_vaultSource).permit(
            msg.sender,
            address(this),
            _vaultSourceSharesAmount,
            _deadline,
            _v,
            _r,
            _s
        );
    }

    function _fundTransfer(
        address _vaultSource,
        uint256 _vaultSourceSharesAmount,
        address _vaultTargeted,
        address _xSwapAddress,
        bytes calldata _xSwapParams
    ) internal {
        IStrategVault sourceVault = IStrategVault(_vaultSource);
        IStrategVault targetVault = IStrategVault(_vaultTargeted);
        IERC20 sourceAsset = IERC20(sourceVault.asset());
        IERC20 targetAsset = IERC20(targetVault.asset());
        
        sourceVault.transferFrom(msg.sender, address(this), _vaultSourceSharesAmount);
        sourceVault.redeem(_vaultSourceSharesAmount, address(this), address(this));
        uint256 amountSource = sourceAsset.balanceOf(address(this));

        if(_xSwapAddress != address(0)) {
            amountSource = _executeSwap(
                address(targetAsset),
                _xSwapAddress,
                _xSwapParams
            );
        }

        targetAsset.approve(address(targetVault), amountSource);
        targetVault.deposit(amountSource, msg.sender);
    }

    function _xFundTransfer(
        address _vaultSource,
        uint256 _vaultSourceSharesAmount,
        address _targetAsset,

        address _factoryTargeted,
        address _vaultTargeted,

        address _xSwapAddress,
        bytes calldata _xSwapParams,

        address _xGatewayAddress,
        bytes calldata _xGatewayParams
    ) internal {
        address sourceAsset = IStrategVault(_vaultSource).asset();
        
        IStrategVault(_vaultSource).transferFrom(msg.sender, address(this), _vaultSourceSharesAmount);
        IStrategVault(_vaultSource).redeem(_vaultSourceSharesAmount, address(this), address(this));
        uint256 amountToTransfer = IERC20(sourceAsset).balanceOf(address(this));

        if(_xSwapAddress != address(0)) {
            amountToTransfer = _executeSwap(
                _targetAsset,
                _xSwapAddress,
                _xSwapParams
            );
        }

        require(gatewayAllowed[_xGatewayAddress], "400");
        IERC20(_targetAsset).approve(_xGatewayAddress, amountToTransfer);
        IStrategXGateway(_xGatewayAddress).migrateToXChainVault{value: msg.value}(
            _targetAsset,
            amountToTransfer,
            _factoryTargeted,
            _vaultTargeted,
            _xGatewayParams
        );
    }

    function _executeSwap(
        address _targetAsset,
        address _xSwapAddress,
        bytes calldata _xSwapParams
    ) internal returns (uint256) {

        (bool success, ) = _xSwapAddress.delegatecall(
            abi.encodeWithSignature(
                "swap(bytes)",
                _xSwapParams
            )
        );

        if (!success) {
            revert(string.concat("swap err"));
        }

        return IERC20(_targetAsset).balanceOf(address(this));
    }
}
