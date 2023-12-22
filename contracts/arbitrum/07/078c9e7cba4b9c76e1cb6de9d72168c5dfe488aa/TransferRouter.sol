pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";

contract TransferRouter is Ownable {

    event TransferETH(address indexed _from, address indexed _to, uint _value);

    constructor(address _safeAddress) {
        transferOwnership(_safeAddress);
    }

    function transfer(
        IERC20 token,
        address to,
        uint256 value
    ) external returns (bool) {
        return token.transferFrom(msg.sender, to, value);
    }

    function transferSelf(
        IERC20 token,
        address to,
        uint256 value
    ) external onlyOwner returns (bool) {
        return token.transfer(to, value);
    }

    function withdraw() external onlyOwner returns (bool) {
        (bool sent, ) = owner().call{value: address(this).balance}("");
        return sent;
    }
}

