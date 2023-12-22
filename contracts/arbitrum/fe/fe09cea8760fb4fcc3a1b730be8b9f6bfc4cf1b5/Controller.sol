pragma solidity 0.5.16;

import "./Address.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./IController.sol";
import "./IStrategy.sol";
import "./IVault.sol";
import "./FeeRewardForwarder.sol";
import "./Governable.sol";

contract Controller is IController, Governable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Used for notifying profit sharing rewards.
    address public feeRewardForwarder;

    // Used for allowing/disallowing smart contract interactions.
    mapping (address => bool) public whitelist;

    // All vaults that we have
    mapping (address => bool) public vaults;

    uint256 public profitSharingNumerator = 5;
    uint256 public constant profitSharingDenominator = 100;

    event SharePriceChangeLog(
      address indexed vault,
      address indexed strategy,
      uint256 oldSharePrice,
      uint256 newSharePrice,
      uint256 timestamp
    );

    modifier validVault(address _vault){
        require(vaults[_vault], "Controller: Vault does not exist");
        _;
    }

    mapping (address => bool) public hardWorkers;

    modifier onlyHardWorkerOrGovernance() {
        require(hardWorkers[msg.sender] || (msg.sender == governance()),
        "Controller: Only hard worker can call this");
        _;
    }

    constructor(address _storage, address _feeRewardForwarder)
    Governable(_storage) public {
        require(_feeRewardForwarder != address(0), "Controller: feeRewardForwarder should not be empty");
        feeRewardForwarder = _feeRewardForwarder;
    }

    function addHardWorker(address _worker) public onlyGovernance {
      require(_worker != address(0), "Controller: _worker must be defined");
      hardWorkers[_worker] = true;
    }

    function removeHardWorker(address _worker) public onlyGovernance {
      require(_worker != address(0), "Controller: _worker must be defined");
      hardWorkers[_worker] = false;
    }

    function hasVault(address _vault) external returns (bool) {
      return vaults[_vault];
    }

    // Only smart contracts will be affected by the whitelist.
    function addToWhitelist(address _target) public onlyGovernance {
        whitelist[_target] = true;
    }

    function removeFromWhitelist(address _target) public onlyGovernance {
        whitelist[_target] = false;
    }

    function setFeeRewardForwarder(address _feeRewardForwarder) public onlyGovernance {
      require(_feeRewardForwarder != address(0), "Controller: New reward forwarder should not be empty");
      feeRewardForwarder = _feeRewardForwarder;
    }

    function setProfitSharingNumerator(uint256 _profitSharingNumerator) public onlyGovernance {
        require(_profitSharingNumerator < profitSharingDenominator, "Controller: profitSharingNumerator cannot go over the set denominator");
        profitSharingNumerator = _profitSharingNumerator;
    }

    function addVaultAndStrategy(address _vault, address _strategy) external onlyGovernance {
        require(_vault != address(0), "Controller: New vault shouldn't be empty");
        require(!vaults[_vault], "Controller: Vault already exists");
        require(_strategy != address(0), "Controller: New strategy shouldn't be empty");

        vaults[_vault] = true;
        // No need to protect against sandwich, because there will be no call to withdrawAll
        // as the vault and strategy is brand new
        IVault(_vault).setStrategy(_strategy);
    }

    function getPricePerFullShare(address _vault) public view returns(uint256) {
        return IVault(_vault).getPricePerFullShare();
    }

    function doHardWork(address _vault) external 
    onlyHardWorkerOrGovernance 
    validVault(_vault) {
        uint256 oldSharePrice = IVault(_vault).getPricePerFullShare();
        IVault(_vault).doHardWork();
        emit SharePriceChangeLog(
          _vault,
          IVault(_vault).strategy(),
          oldSharePrice,
          IVault(_vault).getPricePerFullShare(),
          block.timestamp
        );
    }

    function withdrawAll(address _vault) external 
    onlyGovernance 
    validVault(_vault) {
        IVault(_vault).withdrawAll();
    }

    function setStrategy(
        address _vault,
        address strategy
    ) external
    onlyGovernance
    validVault(_vault) {
        IVault(_vault).setStrategy(strategy);
    }

    // Transfers token in the controller contract to the governance
    function salvage(address _token, uint256 _amount) external onlyGovernance {
        IERC20(_token).safeTransfer(governance(), _amount);
    }

    function salvageStrategy(address _strategy, address _token, uint256 _amount) external onlyGovernance {
        // The strategy is responsible for maintaining the list of
        // salvagable tokens, to make sure that governance cannot come
        // in and take away the coins
        IStrategy(_strategy).salvage(governance(), _token, _amount);
    }

    function notifyFee(address underlying, uint256 fee) external {
      if (fee > 0) {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), fee);
        IERC20(underlying).safeApprove(feeRewardForwarder, 0);
        IERC20(underlying).safeApprove(feeRewardForwarder, fee);
        FeeRewardForwarder(feeRewardForwarder).poolNotifyFixedTarget(underlying, fee);
      }
    }
}
