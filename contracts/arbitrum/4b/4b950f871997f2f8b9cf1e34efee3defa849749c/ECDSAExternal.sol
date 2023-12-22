import "./ECDSA.sol";

library ECDSAExternal {
    function recover(bytes32 hash, bytes memory signature) external pure returns (address) {
        return ECDSA.recover(hash, signature);
    }
}
