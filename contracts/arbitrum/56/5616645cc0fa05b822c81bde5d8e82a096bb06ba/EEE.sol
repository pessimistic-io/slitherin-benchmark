contract EEE {
    error InvalidArgumentError(uint a);
    error Cus2(string b);

    function f1(uint a) external {
        revert InvalidArgumentError(a);
    }

    function f2(string memory b) external {
        revert Cus2(b);
    }
}