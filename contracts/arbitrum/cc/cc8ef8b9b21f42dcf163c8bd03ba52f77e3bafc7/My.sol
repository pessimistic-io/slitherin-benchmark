contract My {
    // mint card bnb
    event test(uint256 value);

    function mintCardETH() public payable {

        payable(msg.sender).transfer(msg.value);
        emit test(msg.value);

    }
}