// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { ERC20Upgradeable, IERC20Upgradeable as IERC20 }      from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable }      from "./ReentrancyGuardUpgradeable.sol";
import { EnumerableSetUpgradeable as EnumerableSet }      from "./EnumerableSetUpgradeable.sol";
import { IBookToken } from "./IBookToken.sol";
import { BookVesting } from "./BookVesting.sol";

contract BookToken is IBookToken, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.UintSet;

    address private crossChainExecutor;
    BookVesting public contributorVestingContract;
    BookVesting public marketingVestingContract;
    bool public crosschainEnabled;
    bool public contractPaused;
    EnumerableSet.UintSet private enabledChains;
    mapping(uint256 => uint256) public gasForBridge;
    mapping(address => bool) public allowedWhilePaused;

    uint256 public availableFutureMint;
    uint256 private constant CONTRIBUTOR_ALLOCATION = 2000000 ether; // 2,000,000
    uint256 private constant DEV_MARKETING_ALLOCATION = 1000000 ether; // 1,000,000
    uint256 private constant INITIAL_CHAIN_MAX_SUPPLY = 30000000 ether; // 30,000,000
    uint256 private contributorMinted;
    uint256 private dev_marketingMinted;

    modifier onlyCrossChain() {
        require(msg.sender == crossChainExecutor, "Caller not authorized");
        require(crosschainEnabled, "Crosschain not enabled");
        _;
    }

    modifier mintValidation(uint256 amount) {
        require(totalSupply() + availableFutureMint + amount <= _maxSupply(), "Amount exceeds maxSupply");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _initialMint,
        uint256 _vestingStart
    ) external initializer {
        __ERC20_init("Book", "BOOK");
        __Ownable_init();
        __ReentrancyGuard_init();
        uint256 _minted;

        _mint(owner(), _initialMint);
        _minted += _initialMint;

        contributorVestingContract = new BookVesting(_vestingStart, CONTRIBUTOR_ALLOCATION, "Contributor Vesting");

        marketingVestingContract = new BookVesting(_vestingStart, DEV_MARKETING_ALLOCATION, "Dev/Marketing Vesting");

        availableFutureMint = INITIAL_CHAIN_MAX_SUPPLY - _minted;
        contractPaused = true;
        allowedWhilePaused[owner()] = true;
    }

    function setAllowedWhilePaused(address account, bool flag) external override onlyOwner {
        allowedWhilePaused[account] = flag;
    }
    
    function unPauseContract() external override onlyOwner {
        require(contractPaused, "Contract already unpaused");
        contractPaused = false;
        emit ContractUnpaused(block.timestamp);
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
        emit BridgeInitiated(msg.sender, amount, block.chainid, toChain);
    }

    function bridgeTo(
        address account, 
        uint256 amount, 
        uint256 fromChain
    ) external override nonReentrant onlyCrossChain mintValidation(amount) {
        require(enabledChains.contains(fromChain), "Given chainId is not enabled");
        _mint(account, amount);
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

    function mintFutureRewards(uint256 amount) external override nonReentrant onlyOwner {
        require(totalSupply() + amount <= _maxSupply(), "Amount exceeds maxSupply");
        require(amount <= availableFutureMint, "Amount exceeds future allowance");
        availableFutureMint -= amount;
        _mint(owner(), amount);
        emit FutureRewardsMinted(owner(), amount, availableFutureMint);
    }

    function mintFutureRewards(uint256 amount, address to) external override nonReentrant onlyOwner {
        require(totalSupply() + amount <= _maxSupply(), "Amount exceeds maxSupply");
        require(amount <= availableFutureMint, "Amount exceeds future allowance");
        availableFutureMint -= amount;
        _mint(to, amount);
        emit FutureRewardsMinted(to, amount, availableFutureMint);
    }

    function mintVestedTokens(uint256 amount, address to) external override nonReentrant {
        require(totalSupply() + amount <= _maxSupply(), "Amount exceeds maxSupply");
        if (msg.sender == address(contributorVestingContract)) {
            require(amount + contributorMinted <= CONTRIBUTOR_ALLOCATION, "Amount exceeds allocation");
            availableFutureMint -= amount;
            contributorMinted += amount;
            _mint(to, amount);
        } else if (msg.sender == address(marketingVestingContract)) {
            require(amount + dev_marketingMinted <= DEV_MARKETING_ALLOCATION, "Amount exceeds allocation");
            availableFutureMint -= amount;
            dev_marketingMinted += amount;
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

    function burn(uint256 amount) external override onlyOwner {
        _burn(msg.sender, amount);
    }

    function getEnabledChains() external view override returns (uint256[] memory) {
        return enabledChains.values();
    }

    function maxSupply() external view override returns (uint256) {
        return _maxSupply();
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (contractPaused) {
            require(allowedWhilePaused[msg.sender] || allowedWhilePaused[to], "Contract is currently paused");
        }
        super.transfer(to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (contractPaused) {
            require(allowedWhilePaused[from] || allowedWhilePaused[to], "Contract is currently paused");
        }
        super.transferFrom(from, to, amount);
        return true;
    }

    function _maxSupply() internal view returns (uint256) {
        if (crosschainEnabled) {
            return INITIAL_CHAIN_MAX_SUPPLY * enabledChains.length();
        } else {
            return INITIAL_CHAIN_MAX_SUPPLY;
        }
    }
}
