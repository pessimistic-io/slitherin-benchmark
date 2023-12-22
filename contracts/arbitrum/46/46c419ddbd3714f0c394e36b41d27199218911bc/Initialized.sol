pragma solidity >=0.8.19;

library Initialized {
    struct Data {
        bool initialized;
    }

    function load(bytes32 id) internal pure returns (Data storage store) {
        bytes32 s = keccak256(abi.encode("xyz.voltz.Initialized", id));
        assembly {
            store.slot := s
        }
    }
}

