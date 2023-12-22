contract Whitelist {
    event Whitelisted(address indexed addr);
    receive() payable external {
        require(msg.value == 0);
        emit Whitelisted(msg.sender);
    }
}