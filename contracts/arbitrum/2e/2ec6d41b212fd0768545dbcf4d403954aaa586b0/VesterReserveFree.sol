// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import {IERC20} from "./IERC20.sol";
import {IMintable} from "./IMintable.sol";
import {IRewardTracker} from "./IRewardTracker.sol";
import {IVesterReserveFree} from "./IVesterReserveFree.sol";
import {IFairAuction} from "./IFairAuction.sol";

contract VesterReserveFree is IVesterReserveFree, Initializable, UUPSUpgradeable {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    address public gov;

    uint256 public vestingDuration;

    uint256 public compensationTimeDiff;

    address public esToken;

    address public claimableToken;

    uint256 public totalSupply;

    address public fairAuction;

    mapping(address => uint256) public balances;

    mapping(address => uint256) public transferredReserveFreeAmounts;
    mapping(address => uint256) public reserveFreeDeduction;

    mapping(address => uint256) public cumulativeClaimAmounts;
    mapping(address => uint256) public claimedAmounts;
    mapping(address => uint256) public depositAmounts;

    mapping(address => uint256) public lastVestingTimes;

    mapping(address => uint256) public bonusRewards;

    mapping(address => bool) public isHandler;

    event Claim(address receiver, uint256 amount);
    event Deposit(address account, uint256 amount);
    event Withdraw(address account, uint256 claimedAmount, uint256 balance);
    event PairTransfer(address indexed from, address indexed to, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    modifier onlyGov() {
        _onlyGov();
        _;
    }

    function _onlyGov() internal view {
        require(msg.sender == gov, "StrategyVault: not authorized");
    }

    function initialize(        
        string memory _name,
        string memory _symbol,
        uint256 _vestingDuration,
        address _esToken,
        address _claimableToken,
        address _fairAuction
    ) public initializer {
        name = _name;
        symbol = _symbol;

        vestingDuration = _vestingDuration;

        esToken = _esToken;
        claimableToken = _claimableToken;

        fairAuction = _fairAuction;

        gov = msg.sender;

        compensationTimeDiff = block.timestamp - 1674220978;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGov {}

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    function setHandlers(address[] memory _handler, bool[] memory _isActive) external onlyGov {
        for(uint256 i = 0; i < _handler.length; i++){
            isHandler[_handler[i]] = _isActive[i];
        }
    }

    function deposit(uint256 _amount) external {
        _deposit(msg.sender, _amount);
    }

    function depositForAccount(address _account, uint256 _amount) external {
        _validateHandler();
        _deposit(_account, _amount);
    }

    function claim() external returns (uint256) {
        return _claim(msg.sender, msg.sender);
    }

    function claimForAccount(address _account, address _receiver) external override returns (uint256) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).transfer(_account, _amount);
    }

    function withdraw() external {
        address account = msg.sender;
        address _receiver = account;

        _claim(account, _receiver);

        uint256 claimedAmount = cumulativeClaimAmounts[account];

        uint256 balance = balances[account];

        uint256 totalVested = balance + claimedAmount;

        require(totalVested > 0, "Vester: vested amount is zero");

        IERC20(esToken).transfer(_receiver, balance);

        _burn(account, balance);

        delete cumulativeClaimAmounts[account];
        delete claimedAmounts[account];
        delete lastVestingTimes[account];

        depositAmounts[account] -= balance;

        emit Withdraw(account, claimedAmount, balance);
    }

    function transferVestableAmount(address _sender, address _receiver) external override {
        _validateHandler();

        uint256 senderReserveFreeAmount = getMaxVestableAmount(_sender);
        uint256 senderDepositAmount = depositAmounts[_sender]; 

        if(senderReserveFreeAmount > senderDepositAmount){
            uint256 diff = senderReserveFreeAmount - senderDepositAmount;

            transferredReserveFreeAmounts[_receiver] = diff;

            reserveFreeDeduction[_sender] = diff;
        }
    }

    function setBonusReward(address _account, uint256 _amount) external override{
        _validateHandler();

        bonusRewards[_account] = _amount;
    }

    function setBonusRewards(address[] memory _account, uint256[] memory _amount) external override {
        _validateHandler();

        for(uint256 i = 0; i < _account.length; i++){
            bonusRewards[_account[i]] = _amount[i];
        }
    }

    function claimable(address _account) public view override returns (uint256) {
        uint256 amount = cumulativeClaimAmounts[_account] - claimedAmounts[_account];

        uint256 nextClaimable = _getNextClaimableAmount(_account);

        return amount + nextClaimable;
    }

    function getMaxVestableAmount(address _account) public view override returns (uint256) {
        uint256 transferedReserveFree = transferredReserveFreeAmounts[_account];
        uint256 deduction = reserveFreeDeduction[_account];

        uint256 camelotAmount = IFairAuction(fairAuction).getExpectedClaimAmount(_account) / 2;
        uint256 bonusReward = bonusRewards[_account];
        
        if(transferedReserveFree + camelotAmount + bonusReward < deduction) {
            return 0;
        }
        
        return transferedReserveFree + camelotAmount + bonusReward - deduction;
    }

    function getTotalVested(address _account) public view returns (uint256) {
        return balances[_account] + cumulativeClaimAmounts[_account];
    }

    function balanceOf(address _account) public view returns (uint256) {
        return balances[_account];
    }

    // empty implementation, tokens are non-transferrable
    function transfer(address /* recipient */, uint256 /* amount */) public returns (bool) {
        revert("Vester: non-transferrable");
    }

    // empty implementation, tokens are non-transferrable
    function allowance(address /* owner */, address /* spender */) public view virtual returns (uint256) {
        return 0;
    }

    // empty implementation, tokens are non-transferrable
    function approve(address /* spender */, uint256 /* amount */) public virtual returns (bool) {
        revert("Vester: non-transferrable");
    }

    // empty implementation, tokens are non-transferrable
    function transferFrom(
        address /* sender */,
        address /* recipient */,
        uint256 /* amount */
    ) public virtual returns (bool) {
        revert("Vester: non-transferrable");
    }

    function getVestedAmount(address _account) public view override returns (uint256) {
        uint256 balance = balances[_account];

        uint256 cumulativeClaimAmount = cumulativeClaimAmounts[_account];

        return balance + cumulativeClaimAmount;
    }

    function _mint(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: mint to the zero address");

        totalSupply = totalSupply + _amount;
        balances[_account] = balances[_account] + _amount;

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: burn from the zero address");

        balances[_account] = balances[_account] - _amount;

        totalSupply = totalSupply - _amount;

        emit Transfer(_account, address(0), _amount);
    }

    function _deposit(address _account, uint256 _amount) private {
        require(_amount > 0, "Vester: invalid _amount");

        uint256 maxAmount = getMaxVestableAmount(_account);

        require(depositAmounts[_account] + _amount <= maxAmount, "Vester: max vestable amount exceeded");

        _updateVesting(_account);

        depositAmounts[_account] += _amount;

        IERC20(esToken).transferFrom(_account, address(this), _amount);

        _mint(_account, _amount);

        emit Deposit(_account, _amount);
    }

    function _updateVesting(address _account) private {
        uint256 amount = _getNextClaimableAmount(_account);

        if(depositAmounts[_account] == 0 && IFairAuction(fairAuction).getExpectedClaimAmount(_account) != 0){
            lastVestingTimes[_account] = block.timestamp - compensationTimeDiff;
        }else{
            lastVestingTimes[_account] = block.timestamp;
        }

        if (amount == 0) {
            return;
        }

        _burn(_account, amount);

        cumulativeClaimAmounts[_account] = cumulativeClaimAmounts[_account] + amount;

        IMintable(esToken).burn(address(this), amount);
    }

    function _getNextClaimableAmount(address _account) private view returns (uint256) {
        uint256 timeDiff = block.timestamp - lastVestingTimes[_account];

        uint256 balance = balances[_account];

        if (balance == 0) {
            return 0;
        }

        uint256 vestedAmount = getVestedAmount(_account);

        uint256 claimableAmount = vestedAmount * timeDiff / vestingDuration;

        if (claimableAmount < balance) {
            return claimableAmount;
        }

        return balance;
    }

    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateVesting(_account);

        uint256 amount = claimable(_account);

        claimedAmounts[_account] = claimedAmounts[_account] + amount;
        IERC20(claimableToken).transfer(_receiver, amount);

        emit Claim(_account, amount);
        return amount;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "Vester: forbidden");
    }
}
