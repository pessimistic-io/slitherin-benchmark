pragma solidity 0.8.10;
contract Test {
    function getChainId() public view returns (uint256) {
        return block.chainid;
    }
}