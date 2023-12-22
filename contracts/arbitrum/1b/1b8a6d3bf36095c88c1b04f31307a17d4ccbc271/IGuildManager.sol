// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Info related to a specific organization. Think of organizations as systems/games. i.e. Bridgeworld, The Beacon, etc.
 * @param guildIdCur The next available guild id within this organization for newly created guilds
 * @param creationRule Describes who can create a guild within this organization
 * @param maxGuildsPerUser The number of guilds a user can join within the organization.
 * @param timeoutAfterLeavingGuild The timeout a user has before joining a new guild after being kicked or leaving another guild
 * @param tokenAddress The address of the 1155 token that represents guilds created within this organization
 * @param maxUsersPerGuildRule Indicates how the max number of users per guild is decided
 * @param maxUsersPerGuildConstant If maxUsersPerGuildRule is set to CONSTANT, this is the max
 * @param customGuildManagerAddress A contract address that handles custom guild creation requirements (i.e owning specific NFTs).
 *  This is used for guild creation if @param creationRule == CUSTOM_RULE
 */
struct GuildOrganizationInfo {
    uint32 guildIdCur;
    GuildCreationRule creationRule;
    uint8 maxGuildsPerUser;
    uint32 timeoutAfterLeavingGuild;
    // Slot 4 (202/256)
    address tokenAddress;
    MaxUsersPerGuildRule maxUsersPerGuildRule;
    uint32 maxUsersPerGuildConstant;
    bool requireTreasureTagForGuilds;
    // Slot 5 (160/256) - customGuildManagerAddress
    address customGuildManagerAddress;
}

/**
 * @dev Contains information about a user at the organization user.
 * @param guildsIdsAMemberOf A list of guild ids they are currently a member/admin/owner of. Excludes invitations
 * @param timeUserLeftGuild The time this user last left or was kicked from a guild. Useful for guild joining timeouts
 */
struct GuildOrganizationUserInfo {
    // Slot 1
    uint32[] guildIdsAMemberOf;
    // Slot 2 (64/256)
    uint64 timeUserLeftGuild;
}

/**
 * @dev Information about a guild within a given organization.
 * @param name The name of this guild
 * @param description A description of this guild
 * @param symbolImageData A symbol that represents this guild
 * @param isSymbolOnChain Indicates if symbolImageData is on chain or is a URL
 * @param currentOwner The current owner of this guild
 * @param usersInGuild Keeps track of the number of users in the guild. This includes MEMBER, ADMIN, and OWNER
 * @param guildStatus Current guild status (active or terminated)
 */
struct GuildInfo {
    // Slot 1
    string name;
    // Slot 2
    string description;
    // Slot 3
    string symbolImageData;
    // Slot 4 (168/256)
    bool isSymbolOnChain;
    address currentOwner;
    uint32 usersInGuild;
    // Slot 5
    mapping(address => GuildUserInfo) addressToGuildUserInfo;
    // Slot 6 (8/256)
    GuildStatus guildStatus;
}

/**
 * @dev Provides information regarding a user in a specific guild
 * @param userStatus Indicates the status of this user (i.e member, admin, invited)
 * @param timeUserJoined The time this user joined this guild
 * @param memberLevel The member level of this user
 */
struct GuildUserInfo {
    // Slot 1 (8+64+8/256)
    GuildUserStatus userStatus;
    uint64 timeUserJoined;
    uint8 memberLevel;
}

enum GuildUserStatus {
    NOT_ASSOCIATED,
    INVITED,
    MEMBER,
    ADMIN,
    OWNER
}

enum GuildCreationRule {
    ANYONE,
    ADMIN_ONLY,
    CUSTOM_RULE
}

enum MaxUsersPerGuildRule {
    CONSTANT,
    CUSTOM_RULE
}

enum GuildStatus {
    ACTIVE,
    TERMINATED
}

interface IGuildManager {
    /**
     * @dev Sets all necessary state and permissions for the contract
     * @param _guildTokenImplementationAddress The token implementation address for guild token contracts to proxy to
     */
    function GuildManager_init(address _guildTokenImplementationAddress) external;

    /**
     * @dev Creates a new guild within the given organization. Must pass the guild creation requirements.
     * @param _organizationId The organization to create the guild within
     */
    function createGuild(bytes32 _organizationId) external;

    /**
     * @dev Terminates a provided guild
     * @param _organizationId The organization of the guild
     * @param _guildId The guild to terminate
     * @param _reason The reason of termination for the guild
     */
    function terminateGuild(bytes32 _organizationId, uint32 _guildId, string calldata _reason) external;

    /**
     * @dev Grants a given user guild terminator priviliges under a certain guild
     * @param _account The user to give terminator
     * @param _organizationId The org they belong to
     * @param _guildId The guild they belong to
     */
    function grantGuildTerminator(address _account, bytes32 _organizationId, uint32 _guildId) external;

    /**
     * @dev Grants a given user guild admin priviliges under a certain guild
     * @param _account The user to give admin
     * @param _organizationId The org they belong to
     * @param _guildId The guild they belong to
     */
    function grantGuildAdmin(address _account, bytes32 _organizationId, uint32 _guildId) external;

    /**
     * @dev Updates the guild info for the given guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to update
     * @param _name The new name of the guild
     * @param _description The new description of the guild
     */
    function updateGuildInfo(
        bytes32 _organizationId,
        uint32 _guildId,
        string calldata _name,
        string calldata _description
    ) external;

    /**
     * @dev Updates the guild symbol for the given guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to update
     * @param _symbolImageData The new symbol for the guild
     * @param _isSymbolOnChain Indicates if symbolImageData is on chain or is a URL
     */
    function updateGuildSymbol(
        bytes32 _organizationId,
        uint32 _guildId,
        string calldata _symbolImageData,
        bool _isSymbolOnChain
    ) external;

    /**
     * @dev Adjusts a given users member level
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild the user is in
     * @param _user The user to adjust
     * @param _memberLevel The memberLevel to adjust to
     */
    function adjustMemberLevel(bytes32 _organizationId, uint32 _guildId, address _user, uint8 _memberLevel) external;

    /**
     * @dev Invites users to the given guild. Can only be done by admins or the guild owner.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to invite users to
     * @param _users The users to invite
     */
    function inviteUsers(bytes32 _organizationId, uint32 _guildId, address[] calldata _users) external;

    /**
     * @dev Accepts an invitation to the given guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to accept the invitation to
     */
    function acceptInvitation(bytes32 _organizationId, uint32 _guildId) external;

    /**
     * @dev Changes the admin status of the given users within the given guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to change the admin status of users within
     * @param _users The users to change the admin status of
     * @param _isAdmins Indicates if the users should be admins or not
     */
    function changeGuildAdmins(
        bytes32 _organizationId,
        uint32 _guildId,
        address[] calldata _users,
        bool[] calldata _isAdmins
    ) external;

    /**
     * @dev Changes the owner of the given guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to change the owner of
     * @param _newOwner The new owner of the guild
     */
    function changeGuildOwner(bytes32 _organizationId, uint32 _guildId, address _newOwner) external;

    /**
     * @dev Leaves the given guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to leave
     */
    function leaveGuild(bytes32 _organizationId, uint32 _guildId) external;

    /**
     * @dev Kicks or cancels any invites of the given users from the given guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to kick users from
     * @param _users The users to kick
     */
    function kickOrRemoveInvitations(bytes32 _organizationId, uint32 _guildId, address[] calldata _users) external;

    /**
     * @dev Returns the current status of a guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to get the status of
     */
    function getGuildStatus(bytes32 _organizationId, uint32 _guildId) external view returns (GuildStatus);

    /**
     * @dev Returns whether or not the given user can create a guild within the given organization.
     * @param _organizationId The organization to check
     * @param _user The user to check
     * @return Whether or not the user can create a guild within the given organization
     */
    function userCanCreateGuild(bytes32 _organizationId, address _user) external view returns (bool);

    /**
     * @dev Returns the membership status of the given user within the given guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to get the membership status of the user within
     * @param _user The user to get the membership status of
     * @return The membership status of the user within the guild
     */
    function getGuildMemberStatus(
        bytes32 _organizationId,
        uint32 _guildId,
        address _user
    ) external view returns (GuildUserStatus);

    /**
     * @dev Returns the guild user info struct of the given user within the given guild.
     * @param _organizationId The organization the guild is within
     * @param _guildId The guild to get the info struct of the user within
     * @param _user The user to get the info struct of
     * @return The info struct of the user within the guild
     */
    function getGuildMemberInfo(
        bytes32 _organizationId,
        uint32 _guildId,
        address _user
    ) external view returns (GuildUserInfo memory);

    /**
     * @dev Initializes the Guild feature for the given organization.
     *  This can only be done by admins on the GuildManager contract.
     * @param _organizationId The id of the organization to initialize
     * @param _maxGuildsPerUser The maximum number of guilds a user can join within the organization.
     * @param _timeoutAfterLeavingGuild The number of seconds a user has to wait before being able to rejoin a guild
     * @param _guildCreationRule The rule for creating new guilds
     * @param _maxUsersPerGuildRule Indicates how the max number of users per guild is decided
     * @param _maxUsersPerGuildConstant If maxUsersPerGuildRule is set to CONSTANT, this is the max
     * @param _customGuildManagerAddress A contract address that handles custom guild creation requirements (i.e owning specific NFTs).
     * @param _requireTreasureTagForGuilds Whether this org requires a treasure tag for guilds
     *  This is used for guild creation if @param _guildCreationRule == CUSTOM_RULE
     */
    function initializeForOrganization(
        bytes32 _organizationId,
        uint8 _maxGuildsPerUser,
        uint32 _timeoutAfterLeavingGuild,
        GuildCreationRule _guildCreationRule,
        MaxUsersPerGuildRule _maxUsersPerGuildRule,
        uint32 _maxUsersPerGuildConstant,
        address _customGuildManagerAddress,
        bool _requireTreasureTagForGuilds
    ) external;

    /**
     * @dev Sets the max number of guilds a user can join within the organization.
     * @param _organizationId The id of the organization to set the max guilds per user for.
     * @param _maxGuildsPerUser The maximum number of guilds a user can join within the organization.
     */
    function setMaxGuildsPerUser(bytes32 _organizationId, uint8 _maxGuildsPerUser) external;

    /**
     * @dev Sets the cooldown period a user has to wait before joining a new guild within the organization.
     * @param _organizationId The id of the organization to set the guild joining timeout for.
     * @param _timeoutAfterLeavingGuild The cooldown period a user has to wait before joining a new guild within the organization.
     */
    function setTimeoutAfterLeavingGuild(bytes32 _organizationId, uint32 _timeoutAfterLeavingGuild) external;

    /**
     * @dev Sets the rule for creating new guilds within the organization.
     * @param _organizationId The id of the organization to set the guild creation rule for.
     * @param _guildCreationRule The rule that outlines how a user can create a new guild within the organization.
     */
    function setGuildCreationRule(bytes32 _organizationId, GuildCreationRule _guildCreationRule) external;

    /**
     * @dev Sets the max number of users per guild within the organization.
     * @param _organizationId The id of the organization to set the max number of users per guild for
     * @param _maxUsersPerGuildRule Indicates how the max number of users per guild is decided within the organization.
     * @param _maxUsersPerGuildConstant If maxUsersPerGuildRule is set to CONSTANT, this is the max.
     */
    function setMaxUsersPerGuild(
        bytes32 _organizationId,
        MaxUsersPerGuildRule _maxUsersPerGuildRule,
        uint32 _maxUsersPerGuildConstant
    ) external;

    /**
     * @dev Sets whether an org requires treasure tags for guilds
     * @param _organizationId The id of the organization to adjust
     * @param _requireTreasureTagForGuilds Whether treasure tags are required
     */
    function setRequireTreasureTagForGuilds(bytes32 _organizationId, bool _requireTreasureTagForGuilds) external;

    /**
     * @dev Sets the contract address that handles custom guild creation requirements (i.e owning specific NFTs).
     * @param _organizationId The id of the organization to set the custom guild manager address for
     * @param _customGuildManagerAddress The contract address that handles custom guild creation requirements (i.e owning specific NFTs).
     *  This is used for guild creation if the saved `guildCreationRule` == CUSTOM_RULE
     */
    function setCustomGuildManagerAddress(bytes32 _organizationId, address _customGuildManagerAddress) external;

    /**
     * @dev Sets the treasure tag nft address
     * @param _treasureTagNFTAddress The address of the treasure tag nft contract
     */
    function setTreasureTagNFTAddress(address _treasureTagNFTAddress) external;

    /**
     * @dev Retrieves the stored info for a given organization. Used to wrap the tuple from
     *  calling the mapping directly from external contracts
     * @param _organizationId The organization to return guild management info for
     * @return The stored guild settings for a given organization
     */
    function getGuildOrganizationInfo(bytes32 _organizationId) external view returns (GuildOrganizationInfo memory);

    /**
     * @dev Retrieves the token address for guilds within the given organization
     * @param _organizationId The organization to return the guild token address for
     * @return The token address for guilds within the given organization
     */
    function guildTokenAddress(bytes32 _organizationId) external view returns (address);

    /**
     * @dev Retrieves the token implementation address for guild token contracts to proxy to
     * @return The beacon token implementation address
     */
    function guildTokenImplementation() external view returns (address);

    /**
     * @dev Determines if the given guild is valid for the given organization
     * @param _organizationId The organization to verify against
     * @param _guildId The guild to verify
     * @return If the given guild is valid within the given organization
     */
    function isValidGuild(bytes32 _organizationId, uint32 _guildId) external view returns (bool);

    /**
     * @dev Get a given guild's name
     * @param _organizationId The organization to find the given guild within
     * @param _guildId The guild to retrieve the name from
     * @return The name of the given guild within the given organization
     */
    function guildName(bytes32 _organizationId, uint32 _guildId) external view returns (string memory);

    /**
     * @dev Get a given guild's description
     * @param _organizationId The organization to find the given guild within
     * @param _guildId The guild to retrieve the description from
     * @return The description of the given guild within the given organization
     */
    function guildDescription(bytes32 _organizationId, uint32 _guildId) external view returns (string memory);

    /**
     * @dev Get a given guild's symbol info
     * @param _organizationId The organization to find the given guild within
     * @param _guildId The guild to retrieve the symbol info from
     * @return symbolImageData_ The symbol data of the given guild within the given organization
     * @return isSymbolOnChain_ Whether or not the returned data is a URL or on-chain
     */
    function guildSymbolInfo(
        bytes32 _organizationId,
        uint32 _guildId
    ) external view returns (string memory symbolImageData_, bool isSymbolOnChain_);

    /**
     * @dev Retrieves the current owner for a given guild within a organization.
     * @param _organizationId The organization to find the guild within
     * @param _guildId The guild to return the owner of
     * @return The current owner of the given guild within the given organization
     */
    function guildOwner(bytes32 _organizationId, uint32 _guildId) external view returns (address);

    /**
     * @dev Retrieves the current owner for a given guild within a organization.
     * @param _organizationId The organization to find the guild within
     * @param _guildId The guild to return the maxMembers of
     * @return The current maxMembers of the given guild within the given organization
     */
    function maxUsersForGuild(bytes32 _organizationId, uint32 _guildId) external view returns (uint32);
}

