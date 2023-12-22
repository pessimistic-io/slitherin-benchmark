// SPDX-License-Identifier: UNLICENSED

// Copyright (c) FloraLoans - All rights reserved
// https://twitter.com/Flora_Loans

// This contract is a wrapper around the LendingPair contract
// Each new LendingPair implementation delegates its calls to this contract
// It enables ERC20 functionality around the postion tokens

pragma solidity 0.8.19;

import "./Ownable2Step.sol";

import "./ILPTokenMaster.sol";
import "./ILendingPair.sol";
import "./ILendingController.sol";

/// @title LendingPairTokenMaster: An ERC20-like Master contract for Flora Loans
/// @author 0xdev & flora.loans
/// @notice This contract serves as a fungible token and is a wrapper around the LendingPair contract
/// @dev Each new LendingPair implementation delegates its calls to this contract, enabling ERC20 functionality around the position tokens
/// @dev Implements the ERC20 standard and serves as the master contract for managing tokens in lending pairs

contract LPTokenMaster is ILPTokenMaster, Ownable2Step {
    mapping(address account => mapping(address spender => uint256 amount))
        public
        override allowance;

    address public override underlying;
    address public lendingController;
    string public constant name = "Flora-Lendingpair";
    string public constant symbol = "FLORA-LP";
    uint8 public constant override decimals = 18;
    bool private _initialized;

    modifier onlyOperator() {
        require(
            msg.sender == ILendingController(lendingController).owner(),
            "LPToken: caller is not an operator"
        );
        _;
    }

    /// @notice Initialize the contract, called by the LendingPair during creation at PairFactory
    /// @param _underlying Address of the underlying token (e.g. WETH address if the token is WETH)
    /// @param _lendingController Address of the lending controller
    function initialize(
        address _underlying,
        address _lendingController
    ) external override {
        require(_initialized != true, "LPToken: already intialized");
        underlying = _underlying;
        lendingController = _lendingController;
        _initialized = true;
    }

    /// @notice Transfer tokens to a specified address
    /// @param _recipient The address to transfer to
    /// @param _amount The amount to be transferred
    /// @return A boolean value indicating whether the operation succeeded
    function transfer(
        address _recipient,
        uint256 _amount
    ) external override returns (bool /* transferSuccessful */) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    /// @notice Approve the passed address to spend the specified amount of tokens on behalf of msg.sender
    /// @param _spender The address which will spend the funds
    /// @param _amount The amount of tokens to be spent
    /// @return A boolean value indicating whether the operation succeeded
    /// @dev Beware that changing an allowance with this method brings the risk that someone may use both the old
    /// and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
    /// race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
    /// https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    function approve(
        address _spender,
        uint256 _amount
    ) external override returns (bool /* approvalSuccesful */) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    /// @notice Transfer tokens from one address to another.
    /// @param _sender The address which you want to send tokens from
    /// @param _recipient The address which you want to transfer to
    /// @param _amount The amount of tokens to be transferred
    /// @return A boolean value indicating whether the operation succeeded
    /// @dev Note that while this function emits an Approval event, this is not required as per the specification and other compliant implementations may not emit the event.
    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external override returns (bool /* transferFromsuccessful */) {
        _approve(_sender, msg.sender, allowance[_sender][msg.sender] - _amount);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    /// @notice Returns the associated LendingPair Contract
    /// @return The address of the associated LendingPair Contract
    function lendingPair()
        external
        view
        override
        returns (address /* LendingPair address */)
    {
        return owner();
    }

    /// @notice Gets the balance of the specified address
    /// @param _account The address to query the balance of
    /// @return A uint256 representing the shares credited to `account`
    function balanceOf(
        address _account
    ) external view override returns (uint256 /* supply shares of `account`*/) {
        return ILendingPair(owner()).supplySharesOf(underlying, _account);
    }

    /// @notice Get the total number of tokens in existence
    /// @return A uint256 representing the total supply of the token
    function totalSupply()
        external
        view
        override
        returns (uint256 /* totalSupplyShares*/)
    {
        return ILendingPair(owner()).totalSupplyShares(underlying);
    }

    /// @notice Returns the current owner of the contract.
    /// @return The address of the current owner. Should be the LendingPair
    function owner()
        public
        view
        override(IOwnable, Ownable)
        returns (address /* owner address */)
    {
        return Ownable.owner();
    }

    /// @notice Allows the pending owner to become the new owner.
    function acceptOwnership() public override(IOwnable, Ownable2Step) {
        return Ownable2Step.acceptOwnership();
    }

    /// @notice Transfers ownership of the contract to a new address.
    /// @param newOwner The address of the new owner.
    function transferOwnership(
        address newOwner
    ) public override(IOwnable, Ownable2Step) {
        return Ownable2Step.transferOwnership(newOwner);
    }

    /// @notice Internal function to transfer tokens between two addresses
    /// @dev Called by the external transfer and transferFrom functions
    /// @param _sender The address from which to transfer tokens
    /// @param _recipient The address to which to transfer tokens
    /// @param _amount The amount of tokens to transfer
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal {
        require(_sender != address(0), "ERC20: transfer from the zero address");
        require(
            _recipient != address(0),
            "ERC20: transfer to the zero address"
        );

        ILendingPair(owner()).transferLp(
            underlying,
            _sender,
            _recipient,
            _amount
        );

        emit Transfer(_sender, _recipient, _amount);
    }

    /// @notice Internal function to approve an address to spend a specified amount of tokens on behalf of an owner
    /// @dev Called by the external approve function
    /// @param _owner The address of the token owner
    /// @param _spender The address to grant spending rights to
    /// @param _amount The amount of tokens to approve for spending
    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(_spender != address(0), "ERC20: approve to the zero address");

        allowance[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }
}

