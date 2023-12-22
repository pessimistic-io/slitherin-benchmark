// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Reflection.sol";
import "./IERC20Burnable.sol";

contract sArbet is Reflection {
    error InsufficientArbetBalance(uint256 _amount, uint256 _balance);
    error InsufficientArbetAllowance(uint256 _amount, uint256 _allowance);
    error InsufficientsArbetBalance(uint256 _amount, uint256 _balance);
    error InsufficientsArbetAllowance(uint256 _amount, uint256 _allowance);
    error ClaimPostponed(address _account);
    error InvalidVault(address vault);

    IERC20 public depositToken;
    IERC20Burnable public arbetToken;

    bool isEntering;

    modifier nonReentrant() {
        require(!isEntering, "Already Entering");
        isEntering = true;
        _;
        isEntering = false;
    }

    constructor(address _arbetAddress, address _depositToken, string memory _name, string memory _symbol) Reflection(_name, _symbol) {
        arbetToken = IERC20Burnable(_arbetAddress);
        depositToken = IERC20(_depositToken);
    }

    function stake(uint256 _amount) external payable nonReentrant {
        address snder = msg.sender;

        require(_amount > 0, "Nothing to stake");

        if(_amount > arbetToken.balanceOf(snder)) {
            revert InsufficientArbetBalance(_amount, arbetToken.balanceOf(snder));
        }

        if(_amount > arbetToken.allowance(snder, address(this))) {
            revert InsufficientArbetAllowance(_amount, arbetToken.allowance(snder, address(this)));
        }

        uint256 oldb = arbetToken.balanceOf(address(this));
        arbetToken.transferFrom(snder, address(this), _amount);
        uint256 newb = arbetToken.balanceOf(address(this));

        _amount = newb - oldb;
        require(_amount > 0, "Zero to stake");

        deposit(snder, _amount);
    }

    function unstake(uint256 _amount) external payable nonReentrant {
        address snder = msg.sender;

        if (_amount > balanceOf(snder)) {
            revert InsufficientsArbetBalance(_amount, balanceOf(snder));
        }

        arbetToken.transfer(snder, _amount);
        withdraw(snder, _amount);
    }

    function addReward(uint256 _reward) external payable nonReentrant onlyProvider {
        if (address(depositToken) == address(0)) {
            _reward = msg.value;
        } else {
            depositToken.transferFrom(msg.sender, address(this), _reward);
        }
        provide(_reward);
    }

    function claimReward() external payable nonReentrant {
        uint256 amount = _claimProvision(msg.sender);
        if (amount == 0) {
            revert ClaimNull(msg.sender);
        }
    }

    function _claimProvision(address user) internal virtual override returns (uint256) {
        uint256 amount = super._claimProvision(user);
        if (amount > 0) {
            if (address(depositToken) == address(0)) {
                payable(user).transfer(amount);
            } else {
                depositToken.transfer(user, amount);
            }
        }
        return amount;
    }

    function setStakingContract(address _newContract) external onlyOwner {
        require(address(arbetToken) != _newContract, "Already Set");
        require(totalSupply() == 0, "Still Staked");
        arbetToken = IERC20Burnable(_newContract);
    }

    function setDepositToken(address _newDepositToken) external onlyOwner {
        require(address(depositToken) != _newDepositToken, "Already Set");
        require(totalSupply() == 0, "Still Staked");
        depositToken = IERC20(_newDepositToken);
    }

    receive() external payable {
    }
}

