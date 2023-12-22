// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./IERC20.sol";
import "./Ownable.sol";
import "./ContextUpgradeable.sol";

contract Airdrop2 is Ownable {
    mapping(address => bool) public whiteList;
    mapping(address => bool) public claimedUser;
    uint256 public counter;
    address public Contract = 0xF531168919B52aCB917E276b1C3E6F485dC6DF6a;
    bool public State = false;
    uint public Share;

    function addList(address[] calldata _list) external onlyOwner {
        require(_list.length <= 10000, "Exceeding maximum limit");
        uint256 i = 0;
        for (i = 0; i < _list.length; i++) {
            if (!whiteList[_list[i]]) {
                whiteList[_list[i]] = true;
            } else {
                continue;
            }
        }
    }

    function changeContract(address _address) external onlyOwner {
        require(_address != address(0), "Cannot be a zero address");
        Contract = _address;
    }

    function changeState(bool _state) external onlyOwner {
        State = _state;
    }

    function changeShare(uint _amount) external onlyOwner {
        Share = _amount;
    }

    function delUser(address _address, bool _state) external onlyOwner {
        require(_address != address(0), "Cannot be a zero address");
        whiteList[_address] = _state;
    }

    function Widthdraw(address _contract) public onlyOwner {
        IERC20 Token = IERC20(_contract);
        Token.transfer(owner(), Token.balanceOf(address(this)));
    }

    function claim(address referrer) public {
        require(State == true, "Not yet open");
        require(whiteList[_msgSender()] == true, "Not on the whitelist");
        require(claimedUser[_msgSender()] == false, "already claimed");
        claimedUser[_msgSender()] = true;
        counter++;
        IERC20 Token = IERC20(Contract);
        Token.transfer(_msgSender(), Share);
        if (referrer != address(0)) {
            Token.transfer(referrer, Share / 10);
        }
    }
}

