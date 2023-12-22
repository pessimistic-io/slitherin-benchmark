// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IFeeConfig.sol";

contract StratFeeManager is Ownable, Pausable {
    struct CommonAddresses {
        address vault;
        address unirouter;
        address keeper;
        address strategist;
        address beefyFeeRecipient;
        address beefyFeeConfig;
    }

    /**
     *@notice Vommon addresses for the strategy
     */
    address public vault;
    address public unirouter;
    address public keeper;
    address public strategist;
    address public beefyFeeRecipient;
    IFeeConfig public beefyFeeConfig;

    uint256 constant DIVISOR = 1 ether;
    uint256 public constant WITHDRAWAL_FEE_CAP = 50;
    uint256 public constant WITHDRAWAL_MAX = 10000;
    uint256 internal withdrawalFee = 10;

    event SetStratFeeId(uint256 feeId);
    event SetWithdrawalFee(uint256 withdrawalFee);
    event SetVault(address vault);
    event SetUnirouter(address unirouter);
    event SetKeeper(address keeper);
    event SetStrategist(address strategist);
    event SetBeefyFeeRecipient(address beefyFeeRecipient);
    event SetBeefyFeeConfig(address beefyFeeConfig);

    constructor(CommonAddresses memory _commonAddresses) {
        vault = _commonAddresses.vault;
        unirouter = _commonAddresses.unirouter;
        keeper = _commonAddresses.keeper;
        strategist = _commonAddresses.strategist;
        beefyFeeRecipient = _commonAddresses.beefyFeeRecipient;
        beefyFeeConfig = IFeeConfig(_commonAddresses.beefyFeeConfig);
    }

    /**
     *@notice Checks that caller is either owner or keeper.
     */
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    /**
     *@notice Fetch fees from config contract
     *@return IFeeConfig.FeeCategory Fees
     */
    function getFees() internal view returns (IFeeConfig.FeeCategory memory) {
        return beefyFeeConfig.getFees(address(this));
    }

    /**
     *@notice Fetch fees from config contract and dynamic deposit/withdraw fees
     *@return IFeeConfig.AllFees Fees
     */
    function getAllFees() external view returns (IFeeConfig.AllFees memory) {
        return IFeeConfig.AllFees(getFees(), depositFee(), withdrawFee());
    }

    /**
     *@notice Get strategy Fee id
     *@return uint256 Strategy fee id
     */
    function getStratFeeId() external view returns (uint256) {
        return beefyFeeConfig.stratFeeId(address(this));
    }

    /**
     *@notice Set strategy fee id
     *@param _feeId Fee id
     */
    function setStratFeeId(uint256 _feeId) external onlyManager {
        beefyFeeConfig.setStratFeeId(_feeId);
        emit SetStratFeeId(_feeId);
    }

    /**
     *@notice Adjust withdrawal fee
     *@param _fee Fee
     */
    function setWithdrawalFee(uint256 _fee) public onlyManager {
        require(_fee <= WITHDRAWAL_FEE_CAP, "!cap");
        withdrawalFee = _fee;
        emit SetWithdrawalFee(_fee);
    }

    /**
     *@notice Set new vault (only for strategy upgrades)
     *@param _vault Vault address
     */
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit SetVault(_vault);
    }

    /**
     *@notice Set new unirouter
     *@param _unirouter Unirouter address
     */
    function setUnirouter(address _unirouter) external onlyOwner {
        unirouter = _unirouter;
        emit SetUnirouter(_unirouter);
    }

    /**
     *@notice Set new keeper to manage strat
     *@param _keeper Kepper address
     */
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
        emit SetKeeper(_keeper);
    }

    /**
     *@notice Set new strategist address to receive strat fees
     *@param _strategist Strategist address
     */
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
        emit SetStrategist(_strategist);
    }

    /**
     *@notice Set new beefy fee address to receive beefy fees
     *@param _beefyFeeRecipient YieldGenius fee recipient address
     */
    function setBeefyFeeRecipient(
        address _beefyFeeRecipient
    ) external onlyOwner {
        beefyFeeRecipient = _beefyFeeRecipient;
        emit SetBeefyFeeRecipient(_beefyFeeRecipient);
    }

    /**
     *@notice Set new fee config address to fetch fees
     *@param _beefyFeeConfig YieldGenius fee config address
     */
    function setBeefyFeeConfig(address _beefyFeeConfig) external onlyOwner {
        beefyFeeConfig = IFeeConfig(_beefyFeeConfig);
        emit SetBeefyFeeConfig(_beefyFeeConfig);
    }

    /**
     *@notice Get deposit fee
     *@return uint256 Deposit fee
     */
    function depositFee() public view virtual returns (uint256) {
        return 0;
    }

    /**
     *@notice Get withdrawal fee
     *@return uint256 Withdraw fee
     */
    function withdrawFee() public view virtual returns (uint256) {
        return paused() ? 0 : withdrawalFee;
    }

    /**
     * @dev Function to synchronize balances before new user deposit.
     * Can be overridden in the strategy.
     */
    function beforeDeposit() external virtual {}
}

