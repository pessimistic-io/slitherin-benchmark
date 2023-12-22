// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./IERC20.sol";
import "./Ownable.sol";
import "./ContextUpgradeable.sol";

contract Airdrop is Ownable {
    mapping(address => bool) public whiteList;
    mapping(address => bool) public claimedUser;
    uint256 public counter;
    address public Contract = 0x81aa95fD8Eb24F9022e61aD3C669e728985E5A88;
    bool public State = true;

    function addList(address[] calldata _list) external onlyOwner {
        require(_list.length < 1000, "Exceeding maximum limit");
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

    function delUser(address _address, bool _state) external onlyOwner {
        require(_address != address(0), "Cannot be a zero address");
        whiteList[_address] = _state;
    }

    function Widthdraw(address _contract) public onlyOwner {
        IERC20 Token = IERC20(_contract);
        Token.transfer(owner(), Token.balanceOf(address(this)));
    }

    function claim() public {
        require(State == true, "Not yet open");
        require(whiteList[_msgSender()] == true, "Not on the whitelist");
        require(claimedUser[_msgSender()] == false, "already claimed");
        claimedUser[_msgSender()] = true;
        IERC20 Token = IERC20(Contract);
        Token.transfer(_msgSender(), 921977642 * 10**6); //1111111111*10**6
    }
}

