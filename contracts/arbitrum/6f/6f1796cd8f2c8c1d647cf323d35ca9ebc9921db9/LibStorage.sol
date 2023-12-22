//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./LibRoleManagement.sol";
import "./LibDexible.sol";
import "./LibRevshare.sol";
import "./LibMultiSig.sol";

library LibStorage {
    bytes32 constant ROLE_STORAGE_KEY = 0xeaae66d228e19ff3fd9a03e3c23ae62eb7fb45b5ce2ee3b6fbdc8dd6b661c819;

    bytes32 constant DEXIBLE_STORAGE_KEY = 0x949817a987a8e038ef345d3c9d4fd28e49d8e4e09456e57c05a8b2ce2e62866c;

    bytes32 constant REVSHARE_STORAGE_KEY = 0xbfa76ec2967ed7f8d3d40cd552f1451ab03573b596bfce931a6a016f7733078c;

    bytes32 constant MULTI_SIG_STORAGE = 0x95345cad9ec96dfc8c5b0a875a5c498451c293011b6404d5fac2627c08bc661c;

    function getRoleStorage() internal pure returns (LibRoleManagement.RoleStorage storage rs) {
        assembly { rs.slot := ROLE_STORAGE_KEY }
    }

    function getDexibleStorage() internal pure returns (LibDexible.DexibleStorage storage ds) {
        assembly { ds.slot := DEXIBLE_STORAGE_KEY }
    }

    function getRevshareStorage() internal pure returns (LibRevshare.RevshareStorage storage rs) {
        assembly { rs.slot := REVSHARE_STORAGE_KEY }
    }

    function getMultiSigStorage() internal pure returns (LibMultiSig.MultiSigStorage storage es) {
        assembly { es.slot := MULTI_SIG_STORAGE }
    }
}
