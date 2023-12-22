pragma solidity 0.8.19;
import {BalancerLoanReceiver} from "./BalancerLoanReceiver.sol";
import {IERC20} from "./IERC20.sol";

struct FlashLoan {
    address[] tokens;
    uint256[] amounts;
}

struct Instruction {
    address to;
    uint256 value;
    bytes data;
}

contract FlashExecutor is BalancerLoanReceiver {

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    address internal owner;
    mapping (address => bool) public managers;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Call(address to, uint256 value, bytes data);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        address _balancerAddress
    ) BalancerLoanReceiver(_balancerAddress) {
        owner = _owner;

        // Set owner as a manager
        managers[_owner] = true;

        // Set own contract as a manager
        managers[address(this)] = true;
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTE
    //////////////////////////////////////////////////////////////*/

    function execute(
        Instruction[] calldata instructions
    ) public payable {
        require(managers[msg.sender], "Only a manager can execute");

        uint256 length = instructions.length;
        for (uint256 i; i < length; i++) {
            address to = instructions[i].to;
            uint256 value = instructions[i].value;
            bytes memory _data = instructions[i].data;

            // If call to external function is not successful, revert
            (bool success, ) = to.call{value: value}(_data);
            require(success, "Call to external function failed");
            emit Call(to, value, _data);
        }
    }

    function flashExecute(
        FlashLoan calldata loan,
        Instruction[] calldata instructions
    ) public payable {
        require(managers[msg.sender], "Only a manager can execute");

        _flashLoanMultipleTokens(
            loan.tokens,
            loan.amounts,
            abi.encode(instructions)
        );
    }

    /*//////////////////////////////////////////////////////////////
                              WITHDRAWALL
    //////////////////////////////////////////////////////////////*/

    function withdrawAll(address token, address recipient) public {
        require(managers[msg.sender], "Only owner or this contract can execute");
        IERC20(token).transfer(recipient, IERC20(token).balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                               MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setManager(address _manager, bool _isManager) external {
        require(owner == msg.sender, "Only owner can call this function");
        managers[_manager] = _isManager;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _flashLoanCallback(
        IERC20[] calldata,
        uint256[] calldata,
        bytes calldata data
    ) internal override {
        Instruction[] memory instructions = abi.decode(data, (Instruction[]));

        uint256 length = instructions.length;
        for (uint256 i; i < length; i++) {
            address to = instructions[i].to;
            uint256 value = instructions[i].value;
            bytes memory _data = instructions[i].data;

            // If call to external function is not successful, revert
            (bool success, ) = to.call{value: value}(_data);
            require(success, "Call to external function failed");
            emit Call(to, value, _data);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    fallback() external payable {}

    receive() external payable {}
}

