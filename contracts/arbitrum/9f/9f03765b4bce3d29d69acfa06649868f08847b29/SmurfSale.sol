// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ECDSA.sol";
import "./ERC20.sol";

contract SmurfSale {
    using ECDSA for bytes32;
    uint256 public constant PRICE = 4;
    uint256 public constant MAX_BY_MINT = 50;
    uint256 public immutable total_elements;
    uint256 public immutable total_elements_public;
    uint256 public left_elements;
    uint256 public left_elements_public;

    mapping(address => bool) public investor;
    mapping(address => bool) public claimed;

    address public baseToken;
    address public farmingToken;
    address public dev;
    address public signerAddr;

    uint256 public depositeTimestamp; // wl time
    uint256 public claimTimestamp;
    bool public initClaimBlock = false;

    modifier onSale() {
        require(depositeTimestamp + 12 * 3600 > block.timestamp, "sale finished");
        _;
    }

    event Deposit(address addr);
    event Claim(address addr);

    constructor(
        address _baseToken,
        address _farmingToken,
        address _dev,
        address _signer,
        uint256 _total,
        uint256 _total_public,
        uint256 _depositeTimestamp
    ) {
        baseToken = _baseToken;
        farmingToken = _farmingToken;
        dev = _dev;
        signerAddr = _signer;
        left_elements = _total;
        total_elements = _total;
        left_elements_public = _total_public;
        total_elements_public = _total_public;
        depositeTimestamp = _depositeTimestamp;
    }

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "!EOA");
        _;
    }

    function deposite(
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public onlyEOA onSale {
        require(depositeTimestamp <= block.timestamp, "!start");
        require(left_elements > 0, "sale out");
        require(!investor[msg.sender], "deposited");
        require(
            keccak256(abi.encodePacked(msg.sender)).toEthSignedMessageHash().recover(v, r, s) == signerAddr,
            "INVALID SIGNATURE."
        );
        IERC20(baseToken).transferFrom(
            msg.sender,
            address(this),
            MAX_BY_MINT * PRICE * 10**(ERC20(baseToken).decimals())
        );
        investor[msg.sender] = true;
        left_elements -= 1;
        emit Deposit(msg.sender);
    }

    function publicDeposite() public onlyEOA onSale {
        require(depositeTimestamp + 2 * 3600 <= block.timestamp, "!start for public");
        require(left_elements_public > 0, "sale out for public");
        require(!investor[msg.sender], "deposited for public");
        IERC20(baseToken).transferFrom(
            msg.sender,
            address(this),
            MAX_BY_MINT * PRICE * 10**(ERC20(baseToken).decimals())
        );
        investor[msg.sender] = true;
        left_elements_public -= 1;
        emit Deposit(msg.sender);
    }

    function claim() public onlyEOA {
        require(initClaimBlock, "!init");
        require(claimTimestamp <= block.timestamp, "!start");
        require(investor[msg.sender], "not investor");
        require(!claimed[msg.sender], "claimed");
        claimed[msg.sender] = true;
        IERC20(farmingToken).transfer(msg.sender, MAX_BY_MINT * 10**(ERC20(farmingToken).decimals()));
        emit Claim(msg.sender);
    }

    function setClaimTimestamp(uint256 _claimTimestamp) public {
        require(msg.sender == dev, "!dev");
        claimTimestamp = _claimTimestamp;
        initClaimBlock = true;
    }

    function setDepositeTimestamp(uint256 _depositTimestamp) public {
        require(msg.sender == dev, "!dev");
        depositeTimestamp = _depositTimestamp;
    }

    function withdraw(address _token) public {
        require(msg.sender == dev, "!dev");
        uint256 b = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(dev, b);
    }

    // function withdrawEth() public {
    //     dev.call{value: address(this).balance}(new bytes(0));
    // }

    function getCurrentTimestamp() external view returns (uint256) {
        return block.timestamp;
    }
}

