//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";
import "./Ownable.sol";

contract MetaTopeMock20 is ERC20, Ownable {
    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {}

    function mint(address _to, uint256 _value) public onlyOwner {
        _mint(_to, _value);
    }

    function burn(address _from, uint256 _value) public onlyOwner {
        _burn(_from, _value);
    }

    function deposit() public payable virtual {
        _mint(msg.sender, msg.value);

        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint _amount) external {
        require(balanceOf(msg.sender) >= _amount, 'Insufficient Balance');
        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(_amount);

        emit Withdrawal(msg.sender, _amount);
    }

    receive() external payable virtual {
        deposit();
    }
}

