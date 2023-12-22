// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {VaultBase} from "./VaultBase.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {IConnectorRouter} from "./IConnectorRouter.sol";
import {IVault1155} from "./IVault1155.sol";
import {Vault1155logic} from "./Vault1155logic.sol";
import {VaultDataTypes} from "./VaultDataTypes.sol";
import {ISVS} from "./ISVS.sol";
import "./IERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";

contract Vault1155 is Initializable, VaultBase, ReentrancyGuardUpgradeable, PausableUpgradeable {

    address internal factory;
    address internal reweighter;
    address internal feeReceiver;    
    //address public svs; 
    uint256 public tranchePeriod;
    uint256 public lastTrancheTime;

    event VITCompositionChanged(address[] VITs, uint256[] newWeights);
    event PoolPaused(address admin);
    event PoolUnpaused(address admin);

    constructor(address _registry) VaultBase (_registry) {

    }

    function initialize(address _factory, address _feeReceiver, address _addressesRegistry) external initializer {
        feeReceiver = _feeReceiver;
        factory = _factory;
        addressesRegistry = _addressesRegistry;
        tranchePeriod = 1 days;
        lastTrancheTime = block.timestamp;        
        __Pausable_init();
    }

    function pause() external onlyVaultAdmin {
        _pause();
        emit PoolPaused(msg.sender);
    }

    function unpause() external onlyVaultAdmin {
        _unpause();
        emit PoolUnpaused(msg.sender);
    }

    function getTotalQuote(uint256 _numShares, uint256 fee) public returns (uint256[] memory) {
        return Vault1155logic.getTotalQuote(IConnectorRouter(swapRouter), vaultData.stable, vaultData.VITs, vaultData.VITAmounts, _numShares, fee);
    }

    function getTotalQuoteWithVIT(address _VITAddress, uint256 _numShares) external returns (uint256[] memory) {
        return Vault1155logic.getTotalQuoteWithVIT(IConnectorRouter(swapRouter), vaultData.stable, vaultData.VITs, vaultData.VITAmounts, _VITAddress, _numShares);
    }

    function mintVaultToken(
        uint256 _numShares, 
        uint256 _stableAmount, 
        uint256[] calldata _amountPerSwap, 
        VaultDataTypes.LockupPeriod _lockup) external nonReentrant whenNotPaused {
        
        calculateTranche();
        
        VaultDataTypes.MintParams memory params = VaultDataTypes.MintParams({
            numShares: _numShares,
            stableAmount: _stableAmount,
            amountPerSwap: _amountPerSwap,
            lockup: _lockup,
            stable: vaultData.stable,
            VITs: vaultData.VITs,
            VITAmounts: vaultData.VITAmounts,
            currentTranche: vaultData.currentTranche,
            swapRouter: swapRouter,
            svs: vaultData.SVS,
            depositFee: vaultData.fee.depositFee,
            vaultAddress: address(this)
        });

        Vault1155logic.mintVaultToken(feeReceiver, params); // <--------- this is throwing

        ISVS(vaultData.SVS).addToTotalSupply(vaultData.currentTranche, _numShares);
    }

    function mintVaultTokenWithVIT(
        uint256 _numShares, 
        uint256 _stableAmount, 
        uint256[] calldata _amountPerSwap, 
        VaultDataTypes.LockupPeriod _lockup, 
        address _mintVITAddress, 
        uint256 _mintVITAmount) external nonReentrant whenNotPaused {
        calculateTranche();
        VaultDataTypes.MintParams memory params = VaultDataTypes.MintParams({
            numShares: _numShares,
            stableAmount: _stableAmount,
            amountPerSwap: _amountPerSwap,
            lockup: _lockup,
            stable: vaultData.stable,
            VITs: vaultData.VITs,
            VITAmounts: vaultData.VITAmounts,
            currentTranche: vaultData.currentTranche,
            swapRouter: swapRouter,
            svs: vaultData.SVS,
            depositFee: vaultData.fee.depositFee,
            vaultAddress: address(this)
        });
        
        Vault1155logic.mintVaultTokenWithVIT(feeReceiver, params, _mintVITAddress, _mintVITAmount);
        ISVS(vaultData.SVS).addToTotalSupply(vaultData.currentTranche, _numShares);
    }

    function calculateTranche() internal {
        uint256 blocktime = block.timestamp;
        uint256 currentMidnight = blocktime - (blocktime % 1 days);
        if(blocktime > lastTrancheTime + tranchePeriod){
            vaultData.currentTranche += vaultData.lockupTimes.length; 
            lastTrancheTime = currentMidnight;
            ISVS(vaultData.SVS).setTokenTrancheTimestamp(vaultData.currentTranche, blocktime);
        }
    }
    
    function approveSwapContract(address _exchangeSwapAddress) external onlyVaultAdmin{
        IERC20(vaultData.stable).approve(_exchangeSwapAddress, 2**256 -1);
    }

    function setReweighter(address _reweighter) external onlyVaultAdmin {
        reweighter = _reweighter;
    }

    function changeVITComposition(address[] memory _newVITs, uint256[] memory _newAmounts) external whenNotPaused{
        require(msg.sender == reweighter, "Only reweighter");
        vaultData.VITs = _newVITs;
        vaultData.VITAmounts = _newAmounts;
        emit VITCompositionChanged(_newVITs, _newAmounts);
    }

    function initiateReweight(address[] memory _VITs, uint256[] memory _amounts) external whenNotPaused {
        Vault1155logic.initiateReweight(
                msg.sender, 
                reweighter, 
                _VITs, 
                _amounts
            ); 
    }

    function redeemUnderlying(uint256 _numShares, uint256 _tranche) nonReentrant whenNotPaused external {
        uint256 lockupEnd = getLockupEnd(_tranche);
        Vault1155logic.redeemUnderlying(
                feeReceiver, 
                msg.sender,
                vaultData.SVS,
                _numShares,
                _tranche,
                lockupEnd,
                vaultData.VITs,
                vaultData.VITAmounts,
                vaultData.fee.redemptionFee,
                vaultData.currentTranche
        );
    }

    function getLockupEnd(uint256 _tranche) public view returns (uint256) {
        return ISVS(vaultData.SVS).tokenTranche(_tranche) + vaultData.lockupTimes[_tranche % vaultData.lockupTimes.length]; 
    }

    function getTotalUnderlying() external view returns (uint256[] memory totalUnderlying) {
        totalUnderlying = Vault1155logic.getTotalUnderlying(vaultData.VITs);
    }

    function getTotalUnderlyingByTranche(uint256 tranche) external view returns (uint256[] memory) {
        return Vault1155logic.getTotalUnderlyingByTranche(
            vaultData.VITs,
            vaultData.VITAmounts,
            vaultData.SVS, 
            tranche
        );
    }
}
