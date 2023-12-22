pragma solidity 0.8.10;

interface IExchangeDecoderRegistry {

    function getDecoder(address) external returns(address);
}

abstract contract IAspisPool {

    struct Action {
        address to; // Address to call.
        uint256 value; // Value to be sent with the call. for example (ETH)
        bytes data; // FuncSig + arguments
    }

    receive() external payable{
        //lets contract receive eth funds
    }

    /// @dev Required to handle the permissions within the whole DAO framework accordingly
    /// @param _where The address of the contract
    /// @param _who The address of a EOA or contract to give the permissions
    /// @param _role The hash of the role identifier
    /// @param _data The optional data passed to the ACLOracle registered.
    /// @return bool
    function hasPermission(
        address _where,
        address _who,
        bytes32 _role,
        bytes memory _data
    ) external virtual returns (bool);
    /// @notice If called, the list of provided actions will be executed.
    /// @dev It run a loop through the array of acctions and execute one by one.
    /// @dev If one acction fails, all will be reverted.
    /// @param _actions The aray of actions
    function execute(uint256 callId, Action[] memory _actions) external virtual returns (bytes[] memory);

    event Executed(address indexed actor, uint256 callId, Action[] actions, bytes[] execResults);

    /// @notice Deposit ETH or any token to this contract with a reference string
    /// @dev Deposit ETH (token address == 0) or any token with a reference
    /// @param _token The address of the token and in case of ETH address(0)
    /// @param _amount The amount of tokens to deposit
    function deposit(
        address _token,
        uint256 _amount
    ) external payable virtual;

    event Deposited(address indexed sender, address indexed token, uint256 amount, uint256 minted, uint256 entranceFee, uint256 fundmanagementFee);
    /// @notice Withdraw tokens or ETH from the DAO with a withdraw reference string
    /// @param _to The target address to send tokens or ETH
    function withdraw(
        address _to
    ) external virtual;

    event Withdrawn(address indexed token, address indexed to, uint256 amount, uint256 rageQuitFee, uint256 fundmanagementFee, uint256 performanceFee);

    function getManager() external virtual returns(address);

    function validateProposal(bytes memory _proposal, address _creator) public virtual view returns(bool);

}

