// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC20Upgradeable.sol";
import "./ERC20PermitUpgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./Initializable.sol";
import "./ERC2771ContextUpgradeable.sol";

import "./IStrategOperatingPaymentToken.sol";
import "./IWETH.sol";


/**
 * @title StrategOperatingPaymentToken
 * @notice A Solidity smart contract extending ERC20 with additional features for payment allowances and execution.
 * @dev This contract allows users to set an operator proxy, approve allowances for specific infrastructure operations, and execute payments with a configurable payment fee.
 */
contract StrategOperatingPaymentToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20BurnableUpgradeable,
    ERC2771ContextUpgradeable,
    IStrategOperatingPaymentToken
{
    address public treasury;
    address public operatorProxy;
    address public weth;
    address public relayer;

    uint256 public paymentFee;

    mapping(address => mapping(address => uint256)) private _operationAllowances;

    mapping(address => mapping(address => bool)) private isSponsor;
    mapping(address => address[]) private sponsors;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    function trustedForwarder() public view override returns (address) {
        return relayer;
    }

    function _msgSender() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    /**
     * @notice Initializes the contract with the provided name and symbol for the ERC20 token.
     * @param _name The name of the ERC20 token.
     * @param _symbol The symbol of the ERC20 token.
     */
    function initialize(string memory _name, string memory _symbol, address _treasury, address _weth, address _relayer)
        public
        initializer
    {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __ERC20Burnable_init();

        treasury = _treasury;
        weth = _weth;
        relayer = _relayer;
    }

    /**
     * @notice Sets the operator proxy address that is allowed to execute payments on behalf of users.
     * @dev Only the contract owner can call this function.
     * @param _treasury The address of the treasury.
     */
    function setTreasury(address _treasury) external {
        if (msg.sender != treasury) revert NotTreasury();
        emit TreasuryChanged(_treasury);
        treasury = _treasury;
    }

    /**
     * @notice Sets the operator proxy address that is allowed to execute payments on behalf of users.
     * @dev Only the contract owner can call this function.
     * @param _operatorProxy The address of the operator proxy.
     */
    function setOperatorProxy(address _operatorProxy) external {
        if (msg.sender != treasury) revert NotTreasury();
        operatorProxy = _operatorProxy;
        emit OperatorProxyChanged(_operatorProxy);
    }

    /**
     * @notice get list of sponsor addresses.
     * @param _spender The payment fee expressed in basis points (1/10000).
     */
    function getSponsors(address _spender) external view returns (address[] memory, uint256[] memory) {
        uint256 sponsorLength = sponsors[_spender].length;
        uint256[] memory amounts = new uint256[](sponsorLength);

        for (uint256 i = 0; i < sponsorLength; i++) {
            uint256 amountAllowed = _operationAllowances[sponsors[_spender][i]][_spender];
            uint256 sponsorBalance = balanceOf(sponsors[_spender][i]);
            amounts[i] = amountAllowed > sponsorBalance ? sponsorBalance : amountAllowed;
        }

        return (sponsors[_spender], amounts);
    }

    /**
     * @notice Sets the payment fee for executing payments on this contract.
     * @param _paymentFee The payment fee expressed in basis points (1/10000).
     */
    function setPaymentFee(uint256 _paymentFee) external {
        if (msg.sender != treasury) revert NotTreasury();
        paymentFee = _paymentFee;
        emit PaymentFeeChanged(_paymentFee);
    }

    /**
     * @notice Mints tokens to the specified address by converting sent Ether to tokens.
     * @param to The address to which the minted tokens will be sent.
     */
    function mint(address to) public payable {
        if (msg.value == 0) revert NoMsgValue();
        _mint(to, msg.value);
    }

    /**
     * @notice Mints tokens to the specified address by converting sent Ether to tokens.
     */
    function mint() public payable {
        if (msg.value == 0) revert NoMsgValue();
        _mint(msg.sender, msg.value);
    }

    /**
     * @notice Mints tokens to the specified address by converting sent Ether to tokens.
     */
    function mintFromWETH(address _receiver, uint256 _amount) public {
        if (_amount == 0) revert NoMsgValue();

        IWETH(weth).transferFrom(_msgSender(), address(this), _amount);
        IWETH(weth).withdraw(_amount);
        _mint(_receiver, _amount);
    }

    /**
     * @notice Burns the specified amount of tokens and sends the equivalent amount of Ether to the caller.
     * @param _amount The amount of tokens to burn.
     */
    function burn(uint256 _amount) public override(ERC20BurnableUpgradeable, IStrategOperatingPaymentToken) {
        if (_amount == 0) revert NoBurnValue();
        _burn(_msgSender(), _amount);
        (bool sentTo,) = _msgSender().call{value: _amount}("");
        require(sentTo, "SOPT: Error on burn");
    }

    /**
     * @notice Burns the specified amount of tokens and sends the equivalent amount of Ether to the caller.
     * @param _to The amount of tokens to burn.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _to, uint256 _amount) public {
        if (_amount == 0) revert NoBurnValue();
        _burn(_msgSender(), _amount);
        (bool sentTo,) = _to.call{value: _amount}("");
        require(sentTo, "SOPT: Error on burn");
    }

    /**
     * @notice Retrieves the operation allowance approved by a user for a specific operator.
     * @param owner The address of the user who approves the allowance.
     * @param spender The address of the operator for which the allowance is approved.
     * @return The amount of the approved operation allowance.
     */
    function operationAllowances(address owner, address spender) public view returns (uint256) {
        return _operationAllowances[owner][spender];
    }

    /**
     * @notice Approves an operator to spend tokens on the caller's behalf for a infrastructure operations.
     * @param spender The address of the operated entity to be approved for spending tokens.
     * @param amount The amount of tokens to be approved for the operations.
     * @return Returns true if the operation is successful.
     */
    function approveOperation(address spender, uint256 amount) public returns (bool) {
        address owner = _msgSender();

        if (amount == 0) {
            if (isSponsor[spender][owner]) _removeSponsor(owner, spender);
        } else {
            if (!isSponsor[spender][owner]) _addSponsor(owner, spender);
        }

        _approveOperation(owner, spender, amount);
        return true;
    }

    function _addSponsor(address _sponsor, address _spender) internal {
        isSponsor[_spender][_sponsor] = true;
        sponsors[_spender].push(_sponsor);
    }

    function _removeSponsor(address _sponsor, address _spender) internal {
        uint256 sponsorLength = sponsors[_spender].length;
        for (uint256 i = 0; i < sponsorLength; i++) {
            if (sponsors[_spender][i] == _sponsor) {
                sponsors[_spender][i] = sponsors[_spender][sponsorLength - 1];
                sponsors[_spender].pop();
                isSponsor[_spender][_sponsor] = false;
                return;
            }
        }
    }

    /**
     * @notice Executes a payment operation on behalf of a user.
     * @dev Only the operator proxy can call this function.
     * @param _for The address of the operated entity.
     * @param _operator The address of the operator executing the payment.
     * @param _amount The amount of tokens to be paid.
     * @return Returns true if the payment operation is successful.
     */
    function executePayment(address _for, address _operator, uint256 _amount) public returns (bool) {
        if (msg.sender != operatorProxy) revert NotOperator();

        _paymentTransfer(_for, _operator, _amount);

        return true;
    }

    /**
     * @notice Executes a payment operation on behalf of a user.
     * @dev Only the operator proxy can call this function.
     * @param _payer The payer address.
     * @param _for The address of the operated entity.
     * @param _operator The address of the operator executing the payment.
     * @param _amount The amount of tokens to be paid.
     * @return Returns true if the payment operation is successful.
     */
    function executePaymentFrom(address _payer, address _for, address _operator, uint256 _amount)
        public
        returns (bool)
    {
        if (msg.sender != operatorProxy) revert NotOperator();

        _spendOperationAllowance(_payer, _for, _amount);
        _paymentTransfer(_payer, _operator, _amount);

        return true;
    }

    function _approveOperation(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "SOPT: approve operation from the zero address");
        require(spender != address(0), "SOPT: approve operation to the zero address");

        _operationAllowances[owner][spender] = amount;
        emit OperationApproval(owner, spender, amount);
    }

    function _spendOperationAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = operationAllowances(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "SOPT: insufficient operation allowance");
            unchecked {
                _approveOperation(owner, spender, currentAllowance - amount);
            }
        }
    }

    //@audit fees not accounted in the parameter amount (may fail if there is not enough sopt tokens)
    //@note Vault is shutdown when gas tokens amout is below a threshold
    function _paymentTransfer(address from, address to, uint256 amount) internal virtual {
        uint256 fees = (amount * paymentFee) / 10000;
        _burn(from, amount + fees);
        (bool sentTo,) = to.call{value: amount}("");
        (bool sentTreasury,) = treasury.call{value: fees}("");

        require(sentTo && sentTreasury, "SOPT: Error on payment");

        emit OperationPayment(from, to, amount + fees);
    }
}

