// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./IBaseToken.sol";

contract BaseToken is IERC20, IBaseToken {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    uint256 public nonStakingSupply;

    address public gov;
    address public pendingGov;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    mapping(address => bool) public nonStakingAccounts;
    mapping(address => bool) public admins;

    bool public inPrivateTransferMode = true;
    mapping(address => bool) public isRecipientAllowed;
    
    event AddressUpdated(string name, address a);

    modifier onlyGov() {
        require(msg.sender == gov, "BaseToken: forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "BaseToken: forbidden");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        gov = msg.sender;
        _mint(msg.sender, _initialSupply);
    }

    // Set addresses
    function setPendingGovFund(address _gov) external onlyGov {
        require(_gov != address(0), "ADDRESS_0");
        pendingGov = _gov;
    }

    function confirmGovFund() external onlyGov {
        gov = pendingGov;
        emit AddressUpdated("govFund", gov);
    }

    function addAdmin(address _account) external onlyGov {
        admins[_account] = true;
    }

    function removeAdmin(address _account) external override onlyGov {
        admins[_account] = false;
    }

    function setInPrivateTransferMode(
        bool _inPrivateTransferMode
    ) external override onlyGov {
        inPrivateTransferMode = _inPrivateTransferMode;
    }

    function setRecipientAllowed(address _handler, bool _status) external onlyGov {
        isRecipientAllowed[_handler] = _status;
    }

    function addNonStakingAccount(address _account) external onlyAdmin {
        require(
            !nonStakingAccounts[_account],
            "BaseToken: _account already marked"
        );
        nonStakingAccounts[_account] = true;
        nonStakingSupply = nonStakingSupply.add(balances[_account]);
    }

    function removeNonStakingAccount(address _account) external onlyAdmin {
        require(nonStakingAccounts[_account], "BaseToken: _account not marked");
        nonStakingAccounts[_account] = false;
        nonStakingSupply = nonStakingSupply.sub(balances[_account]);
    }

    function totalStaked() external view override returns (uint256) {
        return totalSupply.sub(nonStakingSupply);
    }

    function balanceOf(
        address _account
    ) external view override returns (uint256) {
        return balances[_account];
    }

    function stakedBalance(
        address _account
    ) external view override returns (uint256) {
        if (nonStakingAccounts[_account]) {
            return 0;
        }
        return balances[_account];
    }

    function transfer(
        address _recipient,
        uint256 _amount
    ) external override returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(
        address _owner,
        address _spender
    ) external view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(
        address _spender,
        uint256 _amount
    ) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external override returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(
            _amount,
            "BaseToken: transfer amount exceeds allowance"
        );
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "BaseToken: mint to the zero address");

        totalSupply = totalSupply.add(_amount);
        balances[_account] = balances[_account].add(_amount);

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply.add(_amount);
        }

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(
            _account != address(0),
            "BaseToken: burn from the zero address"
        );

        balances[_account] = balances[_account].sub(
            _amount,
            "BaseToken: burn amount exceeds balance"
        );
        totalSupply = totalSupply.sub(_amount);

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply.sub(_amount);
        }

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        require(
            _sender != address(0),
            "BaseToken: transfer from the zero address"
        );
        require(
            _recipient != address(0),
            "BaseToken: transfer to the zero address"
        );

        if (inPrivateTransferMode) {
            require(isRecipientAllowed[_recipient] || isRecipientAllowed[_sender],"BaseToken: _recipient not whitelisted");
        }
        
        balances[_sender] = balances[_sender].sub(
            _amount,
            "BaseToken: transfer amount exceeds balance"
        );
        balances[_recipient] = balances[_recipient].add(_amount);

        if (nonStakingAccounts[_sender]) {
            nonStakingSupply = nonStakingSupply.sub(_amount);
        }
        if (nonStakingAccounts[_recipient]) {
            nonStakingSupply = nonStakingSupply.add(_amount);
        }

        emit Transfer(_sender, _recipient, _amount);
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(
            _owner != address(0),
            "BaseToken: approve from the zero address"
        );
        require(
            _spender != address(0),
            "BaseToken: approve to the zero address"
        );

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }
}

