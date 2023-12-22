
interface IPermit2 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

library Permit2Lib {
    // Same on all networks
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    struct PermitDetails {
        address token;
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    struct PermitSingle {
        PermitDetails details;
        address spender;
        uint256 sigDeadline;
    }

    bytes32 public constant PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");
    bytes32 public constant PERMIT_SINGLE_TYPEHASH = keccak256(
        "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );

    bytes4 private constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    function hashData(address _token, uint160 amount, uint48 expiration, uint48 nonce, address spender, uint256 deadline) external view returns (bytes32) {
        PermitDetails memory details = PermitDetails(_token, amount, expiration, nonce);
        PermitSingle memory single = PermitSingle(details, spender, deadline);

        return hashData(single);
    }

    function hashData(PermitSingle memory permitSingle) private view returns (bytes32) {
        return hashPermit2(permitSingle);
    }

    function hashPermit2(PermitSingle memory permitSingle) private view returns (bytes32) {
        bytes32 domainSeparator = PERMIT2.DOMAIN_SEPARATOR();

        bytes32 detailsHash = keccak256(abi.encode(PERMIT_DETAILS_TYPEHASH, permitSingle.details));
        bytes32 permitSingleHash = keccak256(abi.encode(PERMIT_SINGLE_TYPEHASH, detailsHash, permitSingle.spender, permitSingle.sigDeadline));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitSingleHash));
    }
}

