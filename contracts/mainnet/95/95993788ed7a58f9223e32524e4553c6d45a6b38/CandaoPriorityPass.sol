// SPDX-License-Identifier: UNLISTED

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";

contract CandaoCoordinator is Ownable, Pausable {

    struct ProrityPass {
        // @dev: package price starting
        uint256 priorityPassPrice;

        // @dev: domain lenght in character count
        uint256 domainLength;

        // @dev: 
        uint256 blockNumber;

        // @dev: price transfered from user
        uint256 price;

        // @dev: only for validation
        bool valid;
    }

    struct PriorityPassPackageValue {
        // @dev: character count
        uint256 domainLength;

        // @dev: domain price based on package
        uint256 domainPrice;

        // @dev: total price that should be transfered from user
        uint256 totalPrice;

        // @dev: only for validation
        bool valid;
    }

    // @dev: USDC token address
    IERC20 public token;

    // @dev: available packages with configuration
    mapping (uint256 => PriorityPassPackageValue[]) private _packages;
    uint256[] private _availablePackages;

    mapping (uint256 => uint256) private _domainPricing;

    // @dev: wallet address that holds Candao tokens
    address private wallet;

    // @dev: mapping hosting user PP 
    mapping (address => ProrityPass) private _userInfo;

    // @dev: EVENTS
    event PriorityPassBought(address buyer, string reservationToken, uint256 packageIndex, uint256 price, uint256 domainLength);
    event DomainBought(address buyer, string reservationToken, uint256 price, uint256 domainLength);
    event CDOBought(address buyer, uint256 amount);
    event BadgesAddressUpdated(address newAddress);
    event TokenAddressUpdated(address newAddress);

    constructor(address _token, address _wallet) {
        token = IERC20(_token);
        wallet = _wallet;
    }

    function buyPriorityPass(uint256 packagePrice, string memory domain, string memory reservationToken) external whenNotPaused {
        require(!_userInfo[msg.sender].valid, "CandaoCoordinator: Address isn't allowed to buy domain.");
        
        uint256 characterCount = bytes(domain).length;
        require(characterCount != 0, "CandaoCoordinator: Incorrect domainLength.");

        PriorityPassPackageValue[] memory pricingPackages = _packages[packagePrice];
        uint256 totalPrice = 0;

        for (uint256 i = 0; i < pricingPackages.length; i++) {
            PriorityPassPackageValue memory packageItem = pricingPackages[i];
            if (packageItem.domainLength == characterCount) {
                totalPrice = packageItem.totalPrice;
            }
        }

        require(totalPrice != 0, "CandaoCoordinator: package totalPrice not found.");

        token.transferFrom(msg.sender, wallet, totalPrice);
        _userInfo[msg.sender] = ProrityPass(packagePrice, characterCount, block.number, totalPrice, true);
        emit PriorityPassBought(msg.sender, reservationToken, packagePrice, totalPrice, characterCount);
    }

    function buyCDO(uint256 amount) external {
        require(_userInfo[msg.sender].valid, "CandaoCoordinator: Address isn't allowed to buy CDO tokens.");
        token.transferFrom(msg.sender, wallet, amount);
        emit CDOBought(msg.sender, amount);
    }

    function buyAdditionalDomain(string memory domain, string memory reservationToken) external {
        require(_userInfo[msg.sender].valid, "CandaoCoordinator: Address isn't allowed to buy domain.");
        uint256 characterCount = bytes(domain).length;
        require(characterCount != 0, "CandaoCoordinator: Incorrect domainLength.");

        uint256 domainPrice = _domainPricing[characterCount];
        require(domainPrice != 0, "CandaoCoordinator: Domain pricing not set.");

        token.transferFrom(msg.sender, wallet, domainPrice);
        emit DomainBought(msg.sender, reservationToken, domainPrice, characterCount);
    }

    function addDomainPrice(uint256 domainLength, uint256 price) external onlyOwner {
        _domainPricing[domainLength] = price;
    }

    function addPackageOption(uint256 packagePrice, uint256 domainLength, uint256 domainPrice, uint256 totalPrice) external onlyOwner {
        if (_packages[packagePrice].length == 0) {
            _availablePackages.push(packagePrice);
        }

        PriorityPassPackageValue[] memory pricingPackages = _packages[packagePrice];
        for (uint256 i = 0; i < pricingPackages.length; i++) {
            PriorityPassPackageValue memory packageItem = pricingPackages[i];
            if (packageItem.domainLength == domainLength) {
                revert("CandaoCoordinator: Duplicate package option.");
            }
        }

        _packages[packagePrice].push(PriorityPassPackageValue(domainLength, domainPrice, totalPrice, true));
    }

    function removePackage(uint256 packagePrice) external onlyOwner {
        require(_packages[packagePrice].length != 0, "CandaoCoordinator: Missing package");
        delete _packages[packagePrice];

        for (uint i = 0; i < _availablePackages.length; i++) {
            if (_availablePackages[i] == packagePrice) {
                delete _availablePackages[i];
            }
        }
    }

    function removePackageDomainLength(uint256 packagePrice, uint256 packageValueIndex) external onlyOwner {
        require(packagePrice != 0, "CandaoCoordinator: Package Index can't be 0.");
        require(packageValueIndex != 0, "CandaoCoordinator: Package Value Index can't be 0.");
        require(_packages[packagePrice].length != 0, "CandaoCoordinator: Missing package");
        require(_packages[packagePrice][packageValueIndex].valid, "CandaoCoordinator: Missing package value");
        delete _packages[packagePrice][packageValueIndex];
    }

    function setTokenAddress(address newAddress) external onlyOwner {
        require(address(token) != newAddress, "CandaoCoordinator: newAddress can't same as prev.");
        token = IERC20(newAddress);
        emit TokenAddressUpdated(newAddress); 
    }

    function removePriorityPass() external {
        delete _userInfo[msg.sender];
    }

    function setWalletAddress(address newAddress) external onlyOwner {
        wallet = newAddress;
    }

    function userInfo(address _wallet) public view returns (ProrityPass memory) {
        return _userInfo[_wallet];
    }

    function showPackage(uint256 selectedPackage) public view returns (PriorityPassPackageValue[] memory) {
        return _packages[selectedPackage];
    }

    function showDomainPricing(uint256 characterCount) public view returns (uint256) {
        return _domainPricing[characterCount];
    }

    function showAvailablePackages() public view returns (uint256[] memory) {
        return _availablePackages;
    }
}
