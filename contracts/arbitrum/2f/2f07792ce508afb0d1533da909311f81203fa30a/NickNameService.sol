// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import "./SignVerification.sol";
import "./Strings.sol";
import "./Ownable2StepUpgradeable.sol";
import "./AggregatorV3Interface.sol";

contract NickNameService is Ownable2StepUpgradeable {

    struct PriceEntry {
        uint length;
        uint price;
    }

    struct Domain {
        mapping(uint => Record) records;
        address owner;
        string key;
        uint recordsCount;
        bool virgin;
    }

    struct Record {
        string network;
        string addr;
    }

    struct Reverse {
        int version;
        string data;
    }

    struct ReserveEntry {
        bytes32 domainHash;
        address targetOwner;
    }

    // $2
    // We substract 1 "wei" at this place to replace >= by > for gas optimization purposes
    int256 constant UPDATE_PRICE = 2 * 1 ether * 100 - 1;

    mapping(uint => uint) public pricesPerLengthInUsd;

    mapping(string => Domain) domains;
    mapping(address => Reverse) reverseData;

    AggregatorV3Interface internal priceFeed;
    
    uint public domainsCount;

    mapping(bytes32 => address) reservedDomains;

    mapping(string => uint) public domainUpdateNonces;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // // // //
    // // // //

    modifier verifyNicknameValue(string memory _nickname) {
        bytes memory b = bytes(_nickname);
        require(b.length > 3, "Name should be at least 4 characters");
        require(b.length < 64, "Name should be at most 63 characters");
        require(b[0] > 0x60 && b[0] < 0x7B, "Name should start with a letter"); // a-z

        for(uint i; i < b.length; ++i) {
            bytes1 char = b[i];

            require(
                (char > 0x2F && char < 0x3A) || //9-0
                (char > 0x60 && char < 0x7B) || //a-z
                (char == 0x2D) || //-
                (char == 0x5F) //_
            , "Invalid characters, allowed only lowercase alphanumeric and -_"
            );
        }
        _;
    }

    modifier onlyDomainOwner(address caller, string memory _key) {
        require(domains[_key].owner != address(0), "Name is not registered");
        require(caller == domains[_key].owner, "Sender is not the owner of this name");
        _;
    }

    modifier verifyRecords(Record[] memory _records) {
        
        for (uint i; i < _records.length; ++i) {

            for (uint j; j < _records.length; ++j) {

                require(
                    i == j
                    || keccak256(abi.encodePacked(_records[i].network)) != keccak256(abi.encodePacked(_records[j].network)),
                    string.concat("Duplicate records for network: ", _records[i].network)
                );
            }
        }

        _;
    }

    // // // //
    // // // //

    event RegisterDomain(string key, Record[] _records);
    event UpdateDomain(string key, Record[] _records);

    // // // //
    // // // //

    function getSigner(bytes memory _message, bytes memory _sig) internal pure returns (address) {
        bytes32 ethSignedMessageHash = getEthSignedMessageWithPrefix(Strings.toHexString(uint256(keccak256(_message)), 32));
        return recoverSigner(ethSignedMessageHash, _sig);
    }

    function initialize(address _bnbUsdFeedAddr, PriceEntry[] memory _prices) public initializer {
        __Ownable_init();
        setBnbUsdAggregatorAddress(_bnbUsdFeedAddr);
        setPricesPerLengthInUsd(_prices);
    }

    receive() external payable {}

    function setPricesPerLengthInUsd(PriceEntry[] memory _prices) public onlyOwner {
        
        //Cleaning previous values
        for(uint i = 1; i < 64; ++i) {
            pricesPerLengthInUsd[i] = 0;
        }

        for(uint i; i < _prices.length; ++i) {
            pricesPerLengthInUsd[_prices[i].length] = _prices[i].price;
        }
    }

    function setBnbUsdAggregatorAddress(address _addr) public onlyOwner {
        priceFeed = AggregatorV3Interface(_addr);
    }

    function withdraw(address payable _target, uint _amount) external onlyOwner {
        _target.transfer(_amount);
    }

    function register(string memory _key, Record[] memory _records, Reverse memory newReverse) external payable {
        return dedicatedRegister(msg.sender, _key, _records, newReverse);
    }

    function dedicatedRegister(
        address targetOwner,
        string memory _key,
        Record[] memory _records,
        Reverse memory newReverse
    ) public verifyNicknameValue(_key) verifyRecords(_records) payable {

        require(msg.value * uint(getLatestPrice()) >= calcNicknamePrice(_key) * 1 ether, "Insufficient funds");

        checkIsAvailableForRegister(_key);

        Domain storage newDomain = domains[_key];

        Reverse storage currentReverse = reverseData[targetOwner];
        require(currentReverse.version == 0 || currentReverse.version + 1 == newReverse.version, "Reverse optimistic locking!");
        reverseData[targetOwner] = newReverse;

        newDomain.owner = targetOwner;
        newDomain.key = _key;
        newDomain.virgin = _records.length == 0;
        newDomain.recordsCount = _records.length;

        for (uint i; i < _records.length; ++i) {
            newDomain.records[i] = _records[i];
        }

        domainsCount++;
        
        emit RegisterDomain(_key, _records);
    }

    function dedicatedUpdate(
        string memory _key,
        Record[] memory _records,
        bytes memory _argsSig
    ) external payable {
        return _update(
            getSigner(abi.encode(_key, _records, domainUpdateNonces[_key]), _argsSig),
            _key,
            _records
        );
    }

    function update(
        string memory _key,
        Record[] memory _records
    ) external payable {
        return _update(msg.sender, _key, _records);
    }

    function _update(
        address sender,
        string memory _key,
        Record[] memory _records
    )
        private
        verifyNicknameValue(_key)
        onlyDomainOwner(sender, _key)
        verifyRecords(_records)
    {

        Domain storage domain = domains[_key];

        require(int(msg.value) * getLatestPrice() > UPDATE_PRICE || domain.virgin, "Insufficient funds");

        domain.recordsCount = _records.length;

        if(domain.virgin && _records.length > 0) {
            domain.virgin = false;
        }

        for (uint i; i < _records.length; ++i) {
            domain.records[i] = _records[i];
        }

        ++domainUpdateNonces[_key];

        emit UpdateDomain(_key, _records);
    }

    function reverse() external view returns (int, string memory) {
        Reverse storage data = reverseData[msg.sender];
        return (data.version, data.data);
    }

    function resolve(string memory _key) external view verifyNicknameValue(_key) returns (Record[] memory) {
        
        Domain storage domain = domains[_key];

        require(domain.owner != address(0), "Name is not registered");

        Record[] memory records = new Record[](domain.recordsCount);

        for (uint i; i < domain.recordsCount; ++i) {
            records[i] = domain.records[i];
        }

        return (records);
    }

    function calcNicknamePrice(string memory _key) public view verifyNicknameValue(_key) returns (uint) {
        return Math.max(pricesPerLengthInUsd[bytes(_key).length], 1000);
    }

    function isVirgin(string memory _key) external view verifyNicknameValue(_key) returns (bool) {
        return domains[_key].virgin;
    }

    function checkIsAvailableForRegister(string memory _key) public view {
        require(domains[_key].owner == address(0), "Name already registered");
        bytes32 keyHash = sha256(abi.encodePacked(_key));
        require(reservedDomains[keyHash] == address(0) || reservedDomains[keyHash] == msg.sender, "Name is reserved");
    }

    function getLatestPrice() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return price / int(10 ** (priceFeed.decimals() - 2));
    }

    function reserve(ReserveEntry[] memory entries) external onlyOwner {

        for (uint i; i < entries.length; ++i) {
            reservedDomains[entries[i].domainHash] = entries[i].targetOwner;
        }
    }
}

