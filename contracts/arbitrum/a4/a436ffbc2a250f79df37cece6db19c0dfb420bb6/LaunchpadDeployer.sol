// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Launchpad.sol";

contract LaunchpadDeployer is IDeployer, Ownable {
    uint256 public deployCost = 0.001 ether;

    mapping(address => address) public launchpadByToken;
    mapping(IEnums.LAUNCHPAD_TYPE => uint256) public launchpadCount;
    mapping(IEnums.LAUNCHPAD_TYPE => mapping(uint256 => address))
        public launchpadById;
    mapping(IEnums.LAUNCHPAD_TYPE => mapping(address => uint256))
        public launchpadIdByAddress;
    mapping(IEnums.LAUNCHPAD_TYPE => mapping(address => address[]))
        public userLaunchpadInvested;
    mapping(IEnums.LAUNCHPAD_TYPE => mapping(address => address[]))
        public userLaunchpadCreated;
    mapping(IEnums.LAUNCHPAD_TYPE => mapping(address => mapping(address => bool))) isLaunchpadAdded;

    event launchpadDeployed(
        address launchpad,
        address deployer,
        address tokenSale,
        address tokenPayment,
        IEnums.LAUNCHPAD_TYPE launchPadType,
        string uriData,
        bool refundWhenFinish,
        uint256 startTime,
        uint256 endTime,
        uint256 claimTime,
        uint256 adminTokenSaleFee
    );

    event launchpadDeployedParameter(
        address launchpad,
        uint256 softcap,
        uint256 hardcap,
        uint256 presaleRate,
        uint256 listingRate,
        uint256 minBuyPerParticipant,
        uint256 maxBuyPerParticipant
    );

    event launchpadStateChanged(address launchpad, uint256 state);

    event launchpadRaisedChanged(address launchpad, uint256 newRaisedAmount, uint256 newNeedToRaised);

    event launchpadActionChanged(address launchpad, bool usingWhitelist, uint256 endOfWhitelistTime);

    event launchpadWhitelistUsersChanged(address launchpad, address[] users, uint256 action);

    function createLaunchpad(
        uint256[2] memory _caps,
        uint256[3] memory _times,
        uint256[2] memory _rates,
        uint256[2] memory _limits,
        uint256[2] memory _adminFees,
        address[2] memory _tokens,
        string memory _URIData,
        bool _refundWhenFinish,
        IEnums.LAUNCHPAD_TYPE _launchpadType
    ) public payable {
        _checkCanCreateLaunch(_tokens[0]);
        if (_launchpadType == IEnums.LAUNCHPAD_TYPE.FAIR) {
            require(
                _caps[0] == 0 && _limits[0] == 0 && _limits[1] == 0,
                "Invalid create launch input"
            );
        }
        LaunchPad newLaunchpad = new LaunchPad(
            _caps,
            _times,
            _rates,
            _limits,
            _adminFees,
            _tokens,
            _URIData,
            owner(),
            _refundWhenFinish,
            _launchpadType
        );
        _sendTokenToLaunchContract(
            _rates[0],
            _caps[1],
            _tokens[0],
            _adminFees[0],
            address(newLaunchpad)
        );
        _updateLaunchpadData(
            _launchpadType,
            launchpadCount[_launchpadType],
            address(newLaunchpad),
            _tokens[0]
        );
        newLaunchpad.transferOwnership(msg.sender);
        payable(owner()).transfer(msg.value);
        emit launchpadDeployed(
            address(newLaunchpad),
            msg.sender,
            _tokens[0],
            _tokens[1],
            _launchpadType,
            _URIData,
            _refundWhenFinish,
            _times[0],
            _times[1],
            _times[2],
            _adminFees[0]
        );
        emit launchpadDeployedParameter(
            address(newLaunchpad),
            _caps[0],
            _caps[1],
            _rates[0],
            _rates[1],
            _limits[0],
            _limits[1]
        );
    }

    function getDeployedLaunchpads(
        uint256 startIndex,
        uint256 endIndex,
        IEnums.LAUNCHPAD_TYPE _launchpadType
    ) public view returns (address[] memory) {
        if (endIndex >= launchpadCount[_launchpadType]) {
            endIndex = launchpadCount[_launchpadType] - 1;
        }

        uint256 arrayLength = endIndex - startIndex + 1;
        uint256 currentIndex;
        address[] memory launchpadAddress = new address[](arrayLength);

        for (uint256 i = startIndex; i <= endIndex; i++) {
            launchpadAddress[currentIndex] = launchpadById[_launchpadType][
                startIndex + i
            ];
            currentIndex++;
        }

        return launchpadAddress;
    }

    function setDeployPrice(uint256 _price) external onlyOwner {
        deployCost = _price;
    }

    function addToUserLaunchpad(
        address _user,
        address _token,
        IEnums.LAUNCHPAD_TYPE _launchpadType
    ) external override {
        require(
            launchpadByToken[_token] == msg.sender,
            "Only launchpads can do add"
        );
        if (!isLaunchpadAdded[_launchpadType][_user][msg.sender]) {
            userLaunchpadInvested[_launchpadType][_user].push(msg.sender);
            isLaunchpadAdded[_launchpadType][_user][msg.sender] = true;
        }
    }

    function changeLaunchpadState(address _token, uint256 _newState)
        external
        override
    {
        require(
            launchpadByToken[_token] == msg.sender,
            "Only launchpads can remove"
        );
        emit launchpadStateChanged(launchpadByToken[_token], _newState);
        launchpadByToken[_token] = address(0);
    }

    function changeActionChanged(address launchpad, bool usingWhitelist, uint256 endOfWhitelistTime) external override {
        emit launchpadActionChanged(launchpad, usingWhitelist, endOfWhitelistTime);
    }

    function changeWhitelistUsers(address launchpad, address[] memory users, uint256 action) external override {
        emit launchpadWhitelistUsersChanged(launchpad, users, action);
    }

    function launchpadRaisedAmountChangedReport(
        address _token,
        uint256 _currentRaisedAmount,
        uint256 _currentNeedToRaised
    ) external override {
        require(
            launchpadByToken[_token] == msg.sender,
            "Only launchpads can report"
        );
        emit launchpadRaisedChanged(
            launchpadByToken[_token],
            _currentRaisedAmount,
            _currentNeedToRaised
        );
    }

    function getAllLaunchpads()
        external
        view
        returns (address[] memory, address[] memory)
    {
        uint256 numberOfNormalLaunchpad = launchpadCount[
            IEnums.LAUNCHPAD_TYPE.NORMAL
        ];
        uint256 numberOfFairLaunchpad = launchpadCount[
            IEnums.LAUNCHPAD_TYPE.FAIR
        ];
        address[] memory allNormalLaunchpads = new address[](
            numberOfNormalLaunchpad
        );
        address[] memory allFairLaunchpads = new address[](
            numberOfFairLaunchpad
        );
        uint256 counter = numberOfNormalLaunchpad > numberOfFairLaunchpad
            ? numberOfNormalLaunchpad
            : numberOfFairLaunchpad;
        for (uint256 i = 0; i < counter; i++) {
            if (i < numberOfNormalLaunchpad) {
                allNormalLaunchpads[i] = launchpadById[
                    IEnums.LAUNCHPAD_TYPE.NORMAL
                ][i];
            }
            if (i < numberOfFairLaunchpad) {
                allFairLaunchpads[i] = launchpadById[
                    IEnums.LAUNCHPAD_TYPE.FAIR
                ][i];
            }
        }
        return (allNormalLaunchpads, allFairLaunchpads);
    }

    function getUserContributions(
        address _user,
        IEnums.LAUNCHPAD_TYPE _launchpadType
    )
        external
        view
        returns (uint256[] memory ids, uint256[] memory contributions)
    {
        uint256 count = userLaunchpadInvested[_launchpadType][_user].length;
        ids = new uint256[](count);
        contributions = new uint256[](count);

        for (uint256 i; i < count; i++) {
            address launchpadaddress = userLaunchpadInvested[_launchpadType][
                _user
            ][i];
            ids[i] = launchpadIdByAddress[_launchpadType][launchpadaddress];
            contributions[i] = LaunchPad(launchpadaddress).depositedAmount(
                _user
            );
        }
    }

    function _checkCanCreateLaunch(address _token) private {
        require(msg.value >= deployCost, "Not enough BNB to deploy");
        require(
            launchpadByToken[_token] == address(0),
            "Launchpad already created"
        );
    }

    function _sendTokenToLaunchContract(
        uint256 _presaleRate,
        uint256 _cap,
        address _tokenSale,
        uint256 _adminTokenSaleFee,
        address _launchpad
    ) private {
        uint256 tokensToDistribute = (_presaleRate *
            _cap *
            10**ERC20(_tokenSale).decimals()) / 10**18;
        if (_adminTokenSaleFee > 0) {
            tokensToDistribute +=
                (tokensToDistribute * _adminTokenSaleFee) /
                10000;
        }
        ERC20(_tokenSale).transferFrom(
            msg.sender,
            _launchpad,
            tokensToDistribute
        );
    }

    function _updateLaunchpadData(
        IEnums.LAUNCHPAD_TYPE _launchpadType,
        uint256 _launchpadCount,
        address _launchpad,
        address _token
    ) private {
        launchpadByToken[_token] = _launchpad;
        launchpadById[_launchpadType][_launchpadCount] = _launchpad;
        launchpadIdByAddress[_launchpadType][_launchpad] = _launchpadCount;
        launchpadCount[_launchpadType]++;
        userLaunchpadCreated[_launchpadType][msg.sender].push(_launchpad);
    }
}

