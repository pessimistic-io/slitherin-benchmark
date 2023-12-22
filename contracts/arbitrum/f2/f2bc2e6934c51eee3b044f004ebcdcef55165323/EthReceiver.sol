abstract contract EthReceiver {
    receive() external payable {
        require(msg.sender != tx.origin, "Rejected");
    }
}
