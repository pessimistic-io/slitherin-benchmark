// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { ERC20Upgradeable, IERC20Upgradeable as IERC20 }      from "./ERC20Upgradeable.sol";
import { ERC20SnapshotUpgradeable } from "./ERC20SnapshotUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable }      from "./ReentrancyGuardUpgradeable.sol";
import { EnumerableSetUpgradeable as EnumerableSet }      from "./EnumerableSetUpgradeable.sol";
import { PYESwapTokenVesting } from "./PYESwapTokenVesting.sol";
import { IPYESwapToken } from "./IPYESwapToken.sol";

contract PYESwapToken is 
    IPYESwapToken, 
    ERC20Upgradeable, 
    ERC20SnapshotUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    using EnumerableSet for EnumerableSet.UintSet;

    address private crossChainExecutor;
    PYESwapTokenVesting public contributorVestingContract;
    PYESwapTokenVesting public pyeHolderVestingContract;
    bool public crosschainEnabled;
    bool public contractPaused;
    EnumerableSet.UintSet private enabledChains;
    mapping(uint256 => uint256) public gasForBridge;
    mapping(address => bool) public allowedWhilePaused;

    uint256 private constant CONTRIBUTOR_ALLOCATION = 18333 ether; // 18,333
    uint256 private constant PYE_HOLDER_ALLOCATION = 73333 ether; // 73,333
    uint256 private contributorMinted;
    uint256 private pyeHolderMinted;

    mapping(address => bool) public isStakingContract;
    mapping(address => bool) public rewardMinters;
    mapping(address => bool) public tokenBurners;
    mapping(address => bool) public isSnapshotter;

    mapping (address => uint256) public staked;
    uint256 public totalStaked;
    uint256 public burned;
    uint256 public totalBridgedIn;
    uint256 public totalBridgedOut;
    mapping(uint256 => uint256) public totalBridgedToChain;

    modifier onlyCrossChain() {
        require(msg.sender == crossChainExecutor, "Caller not authorized");
        require(crosschainEnabled, "Crosschain not enabled");
        _;
    }

    modifier onlyRewards() {
        require(rewardMinters[msg.sender], "Caller not authorized");
        _;
    }

    modifier onlyBurners() {
        require(tokenBurners[msg.sender], "Caller not authorized");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _initialMint,
        uint256 _vestingStart,
        address _vestAdmin,
        address _weth
    ) external initializer {
        __ERC20_init("PYESwap", "PYES");
        __Ownable_init();
        __ReentrancyGuard_init();
        _transferOwnership(_vestAdmin);

        _mint(owner(), _initialMint);

        contributorVestingContract = new PYESwapTokenVesting(
            _vestAdmin, 
            _weth,
            address(this),
            _vestingStart, 
            CONTRIBUTOR_ALLOCATION, 
            "Contributor Vesting"
        );

        pyeHolderVestingContract = new PYESwapTokenVesting(
            _vestAdmin, 
            _weth, 
            address(this),
            _vestingStart, 
            PYE_HOLDER_ALLOCATION, 
            "PYE Holder Vesting"
        );

        contractPaused = true;
        allowedWhilePaused[owner()] = true;
        tokenBurners[owner()] = true;
        isSnapshotter[owner()] = true;
    }

    function setAllowedWhilePaused(address account, bool flag) external override onlyOwner {
        allowedWhilePaused[account] = flag;
    }
    
    function unPauseContract(address staking) external override onlyOwner {
        require(contractPaused, "Contract already unpaused");
        require(staking != address(0), "Address 0 not allowed");
        isStakingContract[staking] = true;
        rewardMinters[staking] = true;
        contractPaused = false;
        emit ContractUnpaused(block.timestamp);
    }

    function addStakingContract(address _staking) external override onlyOwner {
        require(!isStakingContract[_staking], "Staking contract already set");
        require(_staking != address(0), "Address 0 not allowed");
        isStakingContract[_staking] = true;
        rewardMinters[_staking] = true;
        emit StakingContractSet(_staking);
    }

    function addRewardMinter(address _minter) external override onlyOwner {
        require(!rewardMinters[_minter], "Address is already minter");
        require(_minter != address(0), "Address 0 not allowed");
        rewardMinters[_minter] = true;
        emit RewardMinterAdded(_minter);
    }

    function removeRewardMinter(address _minter) external override onlyOwner {
        require(rewardMinters[_minter], "Address is not minter");
        rewardMinters[_minter] = false;
        emit RewardMinterRemoved(_minter);
    }

    function addTokenBurner(address _burner) external override onlyOwner {
        require(!tokenBurners[_burner], "Address is already minter");
        require(_burner != address(0), "Address 0 not allowed");
        tokenBurners[_burner] = true;
        emit TokenBurnerAdded(_burner);
    }

    function removeTokenBurner(address _burner) external override onlyOwner {
        require(tokenBurners[_burner], "Address is not minter");
        tokenBurners[_burner] = false;
        emit TokenBurnerRemoved(_burner);
    }

    function setCrossChainExecutor(address _executor, bool revoke) external override onlyOwner {
        crossChainExecutor = revoke ? address(0) : _executor;
        emit CrossChainExecutorSet(revoke ? address(0) : _executor);
    }

    function enableCrossChain(uint256[] calldata _chainIds, uint256[] calldata _gas) external override {
        require(!crosschainEnabled, "Crosschain already enabled");
        require(msg.sender == crossChainExecutor, "Caller not allowed");
        require(_chainIds.length == _gas.length, "Array lengths do not match");
        for (uint i = 0; i < _chainIds.length; i++) {
            enabledChains.add(_chainIds[i]);
            gasForBridge[_chainIds[i]] = _gas[i];
            emit SingleChainEnabled(_chainIds[i], _gas[i], block.timestamp);
        }
        require(enabledChains.contains(block.chainid), "This chain must be enabled");
        crosschainEnabled = true;
        emit CrossChainEnabled(block.timestamp);
    }

    function enableSingleChain(uint256 _chainId, uint256 _gas) external override onlyCrossChain {
        enabledChains.add(_chainId);
        gasForBridge[_chainId] = _gas;
        emit SingleChainEnabled(_chainId, _gas, block.timestamp);
    }

    function disableSingleChain(uint256 _chainId) external override onlyCrossChain {
        enabledChains.remove(_chainId);
        delete gasForBridge[_chainId];
        emit SingleChainDisabled(_chainId, block.timestamp);
    }

    function pauseCrossChain() external override onlyCrossChain {
        require(crosschainEnabled, "Crosschain already paused");
        uint[] memory _chainIds = enabledChains.values();
        for (uint i = 0; i < _chainIds.length; i++) {
            enabledChains.remove(_chainIds[i]);
            delete gasForBridge[_chainIds[i]];
        }
        crosschainEnabled = false;
        emit CrossChainDisabled(block.timestamp);
    }

    // owner grant and revoke Snapshotter role to account.
    function setIsSnapshotter(address account, bool flag) external override onlyOwner {
        isSnapshotter[account] = flag;
    }

    function snapshot() external override {
        require(isSnapshotter[msg.sender], "Caller is not allowed to snapshot");
        _snapshot();
    }

    function bridgeFrom(
        uint256 amount, 
        uint256 toChain
    ) external payable override nonReentrant {
        require(crosschainEnabled, "Crosschain not enabled");
        require(enabledChains.contains(toChain), "Given chainId is not enabled");
        require(msg.value == gasForBridge[toChain], "Value does not cover gas");
        _burn(msg.sender, amount);
        (bool success, ) = crossChainExecutor.call{ value: gasForBridge[toChain] }("");
        require(success, "Transfer reverted");
        totalBridgedOut += amount;
        totalBridgedToChain[toChain] += amount;
        emit BridgeInitiated(msg.sender, amount, block.chainid, toChain);
    }

    function bridgeTo(
        address account, 
        uint256 amount, 
        uint256 fromChain
    ) external override nonReentrant onlyCrossChain {
        require(enabledChains.contains(fromChain), "Given chainId is not enabled");
        _mint(account, amount);
        totalBridgedIn += amount;
        emit BridgeCompleted(account, amount, fromChain, block.chainid);
    }

    function cancelBridge(
        address account, 
        uint256 amount, 
        uint256 toChain
    ) external override nonReentrant onlyCrossChain {
        _mint(account, amount);
        emit BridgeCanceled(account, amount, block.chainid, toChain);
    }

    function mint(address to, uint256 amount) external override nonReentrant onlyRewards {
        _mint(to, amount);
        emit RewardsMinted(to, amount);
    }

    function mintVestedTokens(uint256 amount, address to) external override nonReentrant {
        if (msg.sender == address(contributorVestingContract)) {
            require(amount + contributorMinted <= CONTRIBUTOR_ALLOCATION, "Amount exceeds allocation");
            contributorMinted += amount;
            _mint(to, amount);
        } else if (msg.sender == address(pyeHolderVestingContract)) {
            require(amount + pyeHolderMinted <= PYE_HOLDER_ALLOCATION, "Amount exceeds allocation");
            pyeHolderMinted += amount;
            _mint(to, amount);
        } else {
            revert("Only callable by vesting contracts");
        }
        emit VestedTokensMinted(msg.sender, to, amount);
    }

    function rescueERC20(address token, uint256 amount) external override onlyOwner {
        IERC20(token).transfer(owner(), amount);
        emit TokenRescued(token, amount);
    }

    function burn(uint256 amount) external override onlyBurners {
        _burn(msg.sender, amount);
        burned += amount;
        emit Burn(msg.sender, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (contractPaused) {
            require(allowedWhilePaused[msg.sender] || allowedWhilePaused[to], "Contract is currently paused");
        }
        super.transfer(to, amount);
        return true;
    }

    function transferReward(address to, uint256 amount) external override returns (bool) {
        require(isStakingContract[msg.sender], "Only callable by Staking Contract");
        uint256 currentStaked = staked[to];
        super.transfer(to, amount);
        staked[to] = currentStaked;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (contractPaused) {
            require(allowedWhilePaused[from] || allowedWhilePaused[to], "Contract is currently paused");
        }
        super.transferFrom(from, to, amount);
        return true;
    }

    function getEnabledChains() external view override returns (uint256[] memory) {
        return enabledChains.values();
    }

    // returns the owned amount of tokens, including tokens that are staked in main pool.
    function getOwnedBalance(address account) external override view returns (uint256) {
        return staked[account] + balanceOf(account);
    }

    function getCurrentSnapshotId() external override view returns (uint256) {
        return _getCurrentSnapshotId();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20SnapshotUpgradeable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable)
    {
        if(isStakingContract[to] && from != address(0)) { 
            uint256 newAmountAdd = staked[from] + amount;
            setStaked(from, newAmountAdd);
        }

        if(isStakingContract[from]) {
            uint256 newAmountSub = staked[to] - amount;
            setStaked(to, newAmountSub);
        }

        super._afterTokenTransfer(from, to, amount);
    }

    function setStaked(address holder, uint256 amount) internal  {
        totalStaked = (totalStaked - staked[holder]) + amount;
        staked[holder] = amount;
    }

}
