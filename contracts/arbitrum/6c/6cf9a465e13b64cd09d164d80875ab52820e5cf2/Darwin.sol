pragma solidity 0.8.14;

// SPDX-License-Identifier: MIT

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";

import {StakedDarwin} from "./StakedDarwin.sol";
import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";

import {IDarwin, IStakedDarwin} from "./IDarwin.sol";
import {IDarwinCommunity} from "./IDarwinCommunity.sol";

contract Darwin is IDarwin, ERC20Upgradeable, OwnableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {

    // Roles
    bytes32 public constant COMMUNITY_ROLE = keccak256("COMMUNITY_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant MAINTENANCE_ROLE = keccak256("MAINTENANCE_ROLE");
    bytes32 public constant SECURITY_ROLE = keccak256("SECURITY_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    // Constants
    uint256 private constant _MULTIPLIER = 2**160;
    uint256 public constant INITIAL_SUPPLY = 8e7 ether; // initial supply: 80m
    uint256 public constant MAX_SUPPLY = 75e7 ether; // max supply: 750m

    // Reflections
    uint256 public culmulativeRewardPerToken;
    address[] public excludedFromRewards;
    mapping(address => uint256) private _lastCulmulativeRewards;
    mapping(address => bool) private _isExcludedFromRewards;

    // Pausing
    bool public isPaused;

    // The rewards wallet
    address public rewardsWallet;
    // The DarwinSwap factory address
    IUniswapV2Factory public darwinSwapFactory;
    // The StakedDarwin address
    IStakedDarwin public stakedDarwin;
    // The DarwinMasterChef address
    address public masterChef;
    // The DarwinStaking address
    address public darwinStaking;
    // How much DARWIN has been burnt
    uint256 public totalBurnt;

    modifier notPaused() {
        if(isPaused && !hasRole(COMMUNITY_ROLE, msg.sender)) {
            revert Paused();
        }
        _;
    }

    //////////////////////// INITIALIZER /////////////////////////////////

    function initialize(
        address _darwinCommunity,
        address _vester,
        address _wallet1,
        address _charity,
        address _giveaway,
        address _bounties,
        address _darwinDrop
    ) external initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __darwin_init_unchained(
            _darwinCommunity,
            _vester,
            _wallet1,
            _charity,
            _giveaway,
            _bounties,
            _darwinDrop
        );
        __UUPSUpgradeable_init();
        __ERC20_init_unchained("Darwin Protocol", "DARWIN");
    }

    function __darwin_init_unchained(
        address _darwinCommunity,
        address _vester,
        address _wallet1,
        address _charity,
        address _giveaway,
        address _bounties,
        address _darwinDrop
    ) private onlyInitializing {
        { // scope to avoid stack too deep errors
        // Create StakedDarwin contract
        bytes memory bytecode = type(StakedDarwin).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(address(this)));
        address _stakedDarwin;
        assembly {
            _stakedDarwin := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        stakedDarwin = IStakedDarwin(_stakedDarwin);
        }

        rewardsWallet = 0x3Cc90773ebB2714180b424815f390D937974109B;

        // exclude addresses from receiving rewards
        _setExcludedFromRewards(_msgSender());
        _setExcludedFromRewards(_charity);
        _setExcludedFromRewards(_giveaway);
        _setExcludedFromRewards(_bounties);
        _setExcludedFromRewards(_darwinCommunity);
        _setExcludedFromRewards(_wallet1);
        _setExcludedFromRewards(_darwinDrop);
        _setExcludedFromRewards(rewardsWallet);
        _setExcludedFromRewards(_vester);

        // mint
        _mint(msg.sender, INITIAL_SUPPLY - (13e6 ether));
        _mint(_vester, 13e6 ether);

        // grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MAINTENANCE_ROLE, msg.sender);
        _grantRole(SECURITY_ROLE, msg.sender);
        _grantRole(COMMUNITY_ROLE, _darwinCommunity);
        _grantRole(UPGRADER_ROLE, _darwinCommunity);
        _grantRole(MINTER_ROLE, _vester);

        isPaused = false;
    }

    ////////////////////// SWAP FUNCTIONS ///////////////////////////////////

    function setDarwinSwapFactory(address _darwinSwapFactory) external onlyRole(MAINTENANCE_ROLE) {
        require(address(darwinSwapFactory) == address(0), "DARWIN: DarwinSwap Factory address already set");
        darwinSwapFactory = IUniswapV2Factory(_darwinSwapFactory);
        _grantRole(FACTORY_ROLE, _darwinSwapFactory);
    }

    function setDarwinStaking(address _darwinStaking) external onlyRole(MAINTENANCE_ROLE) {
        require(darwinStaking == address(0), "DARWIN: DarwinStaking address already set");
        darwinStaking = _darwinStaking;
        _setExcludedFromRewards(_darwinStaking);
        _grantRole(MINTER_ROLE, _darwinStaking);
        stakedDarwin.setDarwinStaking(_darwinStaking);
    }

    function setMasterChef(address _masterChef) external onlyRole(MAINTENANCE_ROLE) {
        require(masterChef == address(0), "DARWIN: DarwinMasterChef address already set");
        masterChef = _masterChef;
        _setExcludedFromRewards(_masterChef);
        _grantRole(MINTER_ROLE, _masterChef);
    }

    function registerDarwinSwapPair(address _pair) external onlyRole(FACTORY_ROLE) {
        _setExcludedFromRewards(_pair);
    }

    ////////////////////// REWARDS FUNCTIONS /////////////////////////////////////

    function _getRewardsOwed(uint _cumulativeRewardsPerToken, uint _lastCumulativeRewards, uint _balance) internal pure returns(uint) {
        return ((_cumulativeRewardsPerToken - _lastCumulativeRewards) * _balance) / _MULTIPLIER;
    }

    function _distributeRewardToUser(uint _culmulativeRewardsPerToken, uint _accountsLastCulmulativeRewards, uint _balance, address _account) internal returns(uint newBalance) {
        uint _rewardsOwed = _getRewardsOwed(_culmulativeRewardsPerToken, _accountsLastCulmulativeRewards, _balance);
        if (_rewardsOwed > ERC20Upgradeable.balanceOf(rewardsWallet)) {
            _rewardsOwed = ERC20Upgradeable.balanceOf(rewardsWallet);
        }
        _lastCulmulativeRewards[_account] = _culmulativeRewardsPerToken;
        if (_rewardsOwed > 0) {
            _setBalances(rewardsWallet, _account, _rewardsOwed);
        }
        newBalance = _balance + _rewardsOwed;
    }

    function distributeRewards(uint256 amount) external {
        _updateBalance(msg.sender);
        _setBalances(msg.sender, rewardsWallet, amount);
        _distributeRewards(amount);
    }

    function _distributeRewards(uint256 amount) internal {
        culmulativeRewardPerToken += (amount * _MULTIPLIER) / (totalSupply() - _getExcludedBalances());
    }

    function _getExcludedBalances() internal view returns(uint excludedBalances) {
        address[] memory _excludedAddresses = excludedFromRewards;
        for(uint i = 0; i < _excludedAddresses.length; i++) {
            excludedBalances += super.balanceOf(_excludedAddresses[i]);
        }
    }

    function _setExcludedFromRewards(address account) internal {
        if(_isExcludedFromRewards[account]) return;

        uint _culmulativeRewardPerToken = culmulativeRewardPerToken;
        uint last = _lastCulmulativeRewards[account];
        if(last < _culmulativeRewardPerToken) {
            _distributeRewardToUser(_culmulativeRewardPerToken, last, ERC20Upgradeable.balanceOf(account), account);
        }
        _isExcludedFromRewards[account] = true;
        excludedFromRewards.push(account);
    }

    function _removeExcludedFromRewards(address account) internal {
        if(!_isExcludedFromRewards[account]) return;
        delete _isExcludedFromRewards[account];
        address[] memory _excludedAddresses = excludedFromRewards;
        for(uint i = 0; i < _excludedAddresses.length; i++) {
            if(_excludedAddresses[i] == account) {
                excludedFromRewards[i] = _excludedAddresses[_excludedAddresses.length - 1];
                excludedFromRewards.pop();
                break;
            }
        }
        _lastCulmulativeRewards[account] = culmulativeRewardPerToken;
    }

    function _updateBalance(address account) internal {
        if(_isExcludedFromRewards[account]) return;
        uint _culmulativeRewardPerToken = culmulativeRewardPerToken;
        uint _lastCulmulativeReward = _lastCulmulativeRewards[account];
        if(_culmulativeRewardPerToken > _lastCulmulativeReward) {
            _distributeRewardToUser(_culmulativeRewardPerToken, _lastCulmulativeReward, ERC20Upgradeable.balanceOf(account), account);
        }
    }

    /////////////////////// TRANSFER FUNCTIONS //////////////////////////////////////

    function balanceOf(address account) public view override returns (uint256 balance) {
        balance = super.balanceOf(account);
        uint256 sBalance = stakedDarwin.balanceOf(account);
        if (!_isExcludedFromRewards[account]) {
            balance += _getRewardsOwed(culmulativeRewardPerToken, _lastCulmulativeRewards[account], balance + sBalance);
        }
    }

    function _beforeTokenTransfer(address from, address to) internal override notPaused {
        _updateBalance(from);
        _updateBalance(to);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._afterTokenTransfer(from, to, amount);
        if(to == rewardsWallet) {
            _distributeRewards(amount);
        }
    }

    function bulkTransfer(address[] calldata recipients, uint256[] calldata amounts) external {
        if (recipients.length != amounts.length) revert InvalidArrayLengths();
        for (uint256 i = 0; i < recipients.length; ) {
            _transfer(msg.sender, recipients[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > MAX_SUPPLY) revert MaxSupplyReached();
        _mint(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        totalBurnt += amount;
    }

    ////////////////////// COMMUNITY FUNCTIONS /////////////////////////////////////

    function setMinter(address user_, bool canMint_) external onlyRole(COMMUNITY_ROLE) {
        if (canMint_) {
            _grantRole(MINTER_ROLE, user_);
        } else {
            _revokeRole(MINTER_ROLE, user_);
        }
    }

    function setMaintenance(address _account, bool _hasRole) external onlyRole(COMMUNITY_ROLE) {
        if (_hasRole) {
            _grantRole(MAINTENANCE_ROLE, _account);
        } else {
            _revokeRole(MAINTENANCE_ROLE, _account);
        }
    }

    function setSecurity(address _account, bool _hasRole) external onlyRole(COMMUNITY_ROLE) {
        if (_hasRole) {
            _grantRole(SECURITY_ROLE, _account);
        } else {
            _revokeRole(SECURITY_ROLE, _account);
        }
    }

    function setUpgrader(address _account, bool _hasRole) external onlyRole(COMMUNITY_ROLE) {
        if (_hasRole) {
            _grantRole(UPGRADER_ROLE, _account);
        } else {
            _revokeRole(UPGRADER_ROLE, _account);
        }
    }

    function setReceiveRewards(address account, bool shouldReceive) external onlyRole(COMMUNITY_ROLE) {
        if (shouldReceive) {
            _removeExcludedFromRewards(account);
        } else {
            _setExcludedFromRewards(account);
        }
    }

    function communityPause() external onlyRole(COMMUNITY_ROLE) {
        if(!isPaused) {
            isPaused = true;
        }

        emit SetPaused(block.timestamp);
    }

    function communityUnPause() external onlyRole(COMMUNITY_ROLE) {
        if(isPaused) {
            isPaused = false;
        }

        emit SetUnpaused(block.timestamp);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE){}

}
