// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IMuchoToken.sol";
import "./VaultInfo.sol";

/*
CONTRATO MuchoVault:

Punto de entrada para deposit/withdraw del inversor
No guarda liquidez. Potencialmente upgradeable
Guarda una estructura por cada vault. 
En caso de upgrade deberíamos crear estructura gemela en el nuevo contrato
Es el owner de los MuchoToken, receipt tokens de cada vault, por tanto es quien puede mintearlos o quemarlos
Es el owner de MuchoController, para hacer operaciones internas
En caso de upgrade tendría que transferir estos ownerships
Owner: protocolOwner

Operaciones públicas (inversor): deposit, withdraw
Operaciones de configuración (owner o trader): añadir, abrir o cerrar vault
Operaciones de upgrade (owner): cambiar direcciones de los contratos a los que se conecta
*/

interface IMuchoVault{
    event Deposited(address user, uint8 vaultId, uint256 amount, uint256 totalStakedAfter);
    event Withdrawn(address user, uint8 vaultId, uint256 amount, uint256 mamount, uint256 totalStakedAfter);
    event Swapped(address user, uint8 sourceVaultId, uint256 amountSourceMToken, uint8 destVaultId, uint256 amountOutExpected, uint256 amountOutActual, uint256 amountMTokenOwner);
    
    event VaultAdded(IERC20Metadata depositToken, IMuchoToken muchoToken);
    event VaultOpen(uint8 vaultId);
    event VaultClose(uint8 vaultId);
    event DepositFeeChanged(uint8 vaultId, uint16 fee);
    event WithdrawFeeChanged(uint8 vaultId, uint16 fee);
    event VaultUpdated(uint8 vaultId, uint256 amountBefore, uint256 amountAfter);
    event MuchoHubChanged(address newContract);
    event PriceFeedChanged(address newContract);
    event BadgeManagerChanged(address newContract);
    event EarningsAddressChanged(address newAddr);
    event AprUpdatePeriodChanged(uint256 secs);
    event SwapMuchoTokensFeeChanged(uint256 percent);
    event SwapMuchoTokensFeeForPlanChanged(uint256 planId, uint256 percent);
    event SwapMuchoTokensFeeForPlanRemoved(uint256 planId);

    function deposit(uint8 _vaultId, uint256 _amount) external;
    function withdraw(uint8 _vaultId, uint256 _share) external;
    
    function swap(uint8 _sourceVaultId, uint256 _amountSourceMToken, uint8 _destVaultId, uint256 _amountOutExpected, uint16 _maxSlippage) external;

    function addVault(IERC20Metadata _depositToken, IMuchoToken _muchoToken) external returns(uint8);
    function setOpenVault(uint8 _vaultId, bool open) external;
    function setOpenAllVault(bool _open) external;
    function setDepositFee(uint8 _vaultId, uint16 _fee) external;
    function setWithdrawFee(uint8 _vaultId, uint16 _fee) external;

    function refreshAndUpdateAllVaults() external;

    function setMuchoHub(address _newContract) external;
    function setPriceFeed(address _contract) external;
    function setBadgeManager(address _contract) external;
    function setEarningsAddress(address _addr) external;

    function setSwapMuchoTokensFee(uint256 _percent) external;
    function setSwapMuchoTokensFeeForPlan(uint256 _planId, uint256 _percent) external;
    function removeSwapMuchoTokensFeeForPlan(uint256 _planId) external;

    function getSwap(uint8 _sourceVaultId, uint256 _amountSourceMToken, uint8 _destVaultId) external view returns(uint256);
    function getVaultInfo(uint8 _vaultId) external view returns(VaultInfo memory);


    function getDepositFee(uint8 _vaultId, uint256 _amount) external view returns(uint256);
    function getWithdrawalFee(uint8 _vaultId, uint256 _amount) external view returns(uint256);
    function vaultTotalUSD(uint8 _vaultId) external view returns (uint256);
    function allVaultsTotalUSD() external view returns (uint256);
    function investorVaultTotalStaked(uint8 _vaultId, address _user) external view returns (uint256);
    function investorVaultTotalUSD(uint8 _vaultId, address _user) external view returns (uint256);
    function investorTotalUSD(address _user) external view returns (uint256);
    function muchoTokenToDepositTokenPrice(uint8 _vaultId) external view returns (uint256);
    function getExpectedAPR(uint8 _vaultId, uint256 _additionalAmount) external view returns(uint256);
}
