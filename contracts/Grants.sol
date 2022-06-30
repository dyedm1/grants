// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Grants {
    using Counters for Counters.Counter;

    struct grantedTokens {
        //must be of equal length
        address[] tokens;
        uint256[] amounts;
    }
    struct Grant {
        uint256 granter;
        //optional if rawGrantee is set
        uint256 grantee;
        uint256 unlockTime;
        grantedTokens tokens;
        //optional, for grantees that have not created an org beforehand
        address rawGrantee;
    }
    struct grantProp {
        Grant proposedGrant;
        Counters.Counter confirmations;
    }
    struct grantRevokeProp {
        uint256 proposedIdToRevoke;
        Counters.Counter confirmations;
    }

    struct Withdrawal {
        address token;
        uint256 amount;
        address destination;
        Counters.Counter confirmations;
    }
    //this is so we can sequentially generate org ids
    Counters.Counter public _organizationId;
    Counters.Counter public _activeGrantId;
    //mappings holding org data
    mapping(uint256 => mapping(address => bool)) public members;
    mapping(uint256 => mapping(address => uint256)) public balances;
    mapping(uint256 => uint8) requiredConfirmations;
    mapping(uint256 => Counters.Counter) public withdrawalIds;
    mapping(uint256 => mapping(uint256 => mapping(address => bool)))
        public votedWithdrawals;
    mapping(uint256 => mapping(uint256 => Withdrawal)) public withdrawals;
    mapping(uint256 => Counters.Counter) public proposedGrantIds;
    mapping(uint256 => mapping(uint256 => mapping(address => bool)))
        public votedGrant;
    mapping(uint256 => mapping(uint256 => grantProp)) public proposedGrants;
    mapping(uint256 => Counters.Counter) public proposedGrantRevokeIds;
    mapping(uint256 => mapping(uint256 => mapping(address => bool)))
        public votedGrantRevoke;
    mapping(uint256 => mapping(uint256 => grantRevokeProp))
        public proposedGrantRevokes;
    mapping(uint256 => Grant) public activeGrants;
    //indexes of grants by funder and recipient for claim/cancel all functions
    //going thru these is kinda gas inefficient but it makes frontend code easier to write
    //and batch claim/cancel improves ux a decent bit
    mapping(uint256 => uint256[]) public grantedGrantList;
    mapping(uint256 => uint256[]) public pendingGrantList;
    mapping(address => uint256[]) public pendingGrantRawGrantList;

    modifier onlyMember(uint256 orgId) {
        require(
            members[orgId][msg.sender] == true,
            "Only members can call this function"
        );
        _;
    }
    event orgCreated(
        uint256 indexed orgId,
        address[] members,
        uint8 requiredConfirmations
    );

    //could have had an add/remove member function but I'm falling asleep and this contract is massive
    function createOrg(
        address[] calldata _members,
        uint8 _requiredConfirmations
    ) public returns (uint256) {
        require(
            _requiredConfirmations != 0,
            "requiredConfirmations must be greater than 0"
        );
        _organizationId.increment();
        for (uint256 i = 0; i < _members.length; ++i) {
            members[_organizationId.current()][_members[i]] = true;
        }
        requiredConfirmations[
            _organizationId.current()
        ] = _requiredConfirmations;
        emit orgCreated(
            _organizationId.current(),
            _members,
            _requiredConfirmations
        );
        return _organizationId.current();
    }

    event Deposit(
        uint256 indexed orgId,
        address indexed deposistor,
        address tokenAddress,
        uint256 amount
    );

    function deposit(
        uint256 orgId,
        address token,
        uint256 amount
    ) public {
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Failed to transfer token"
        );
        balances[orgId][token] += amount;
        emit Deposit(orgId, msg.sender, token, amount);
    }

    event withdrawalProposed(
        uint256 indexed orgId,
        uint256 indexed withdrawalId,
        address indexed proposer,
        address destination,
        address tokenAddress,
        uint256 amount
    );
    event withdrawal(
        uint256 indexed orgId,
        uint256 indexed withdrawalId,
        address destination,
        address tokenAddress,
        uint256 amount
    );

    function proposeWithdrawal(
        uint256 orgId,
        address destination,
        address token,
        uint256 amount
    ) public onlyMember(orgId) {
        require(
            balances[orgId][token] >= amount,
            "Insufficient balance for withdrawal"
        );
        //shortcut for orgs that only require one confirmation
        if (requiredConfirmations[orgId] == 1) {
            require(
                IERC20(token).transfer(destination, amount),
                "Failed to transfer token, destination may be blacklisted"
            );
            balances[orgId][token] -= amount;

            withdrawalIds[orgId].increment();
            emit withdrawal(
                orgId,
                withdrawalIds[orgId].current(),
                destination,
                token,
                amount
            );
        } else {
            withdrawalIds[orgId].increment();
            uint256 id = withdrawalIds[orgId].current();
            withdrawals[orgId][id] = Withdrawal(
                token,
                amount,
                destination,
                Counters.Counter(1)
            );
            emit withdrawalProposed(
                orgId,
                id,
                msg.sender,
                destination,
                token,
                amount
            );
        }
    }

    function confirmWithdrawal(uint256 orgId, uint256 withdrawalId)
        public
        onlyMember(orgId)
    {
        require(votedWithdrawals[orgId][withdrawalId][msg.sender] == false);
        require(
            withdrawals[orgId][withdrawalId].confirmations.current() <
                requiredConfirmations[orgId],
            "withdrawal has already been performed"
        );
        withdrawals[orgId][withdrawalId].confirmations.increment();
        votedWithdrawals[orgId][withdrawalId][msg.sender] = true;
        require(
            balances[orgId][withdrawals[orgId][withdrawalId].token] >=
                withdrawals[orgId][withdrawalId].amount,
            "Insufficient balance for withdrawal"
        );
        if (
            withdrawals[orgId][withdrawalId].confirmations.current() ==
            requiredConfirmations[orgId]
        ) {
            require(
                IERC20(withdrawals[orgId][withdrawalId].token).transfer(
                    withdrawals[orgId][withdrawalId].destination,
                    withdrawals[orgId][withdrawalId].amount
                ),
                "Failed to transfer token, destination may be blacklisted"
            );

            balances[orgId][
                withdrawals[orgId][withdrawalId].token
            ] -= withdrawals[orgId][withdrawalId].amount;
            emit withdrawal(
                orgId,
                withdrawalId,
                withdrawals[orgId][withdrawalId].destination,
                withdrawals[orgId][withdrawalId].token,
                withdrawals[orgId][withdrawalId].amount
            );
        }
    }

    event grantProposed(
        uint256 indexed granter,
        uint256 indexed grantId,
        uint256 indexed grantee,
        uint256 unlockTime,
        grantedTokens tokens
    );
    event grantActivated(
        uint256 indexed granter,
        uint256 indexed pendingGrantId,
        uint256 indexed grantee,
        uint256 activeGrantId,
        uint256 unlockTime,
        grantedTokens tokens
    );

    //rawGrantee will be 0x0 if grantee is an org, vice versa for grantee if it is an account
    function proposeGrant(
        uint256 orgId,
        uint256 grantee,
        uint256 unlockTime,
        grantedTokens memory tokens,
        address rawGrantee
    ) public onlyMember(orgId) {
        require(
            tokens.tokens.length == tokens.amounts.length,
            "tokens and amounts must be of equal length"
        );
        proposedGrantIds[orgId].increment();
        uint256 proposedGrantId = proposedGrantIds[orgId].current();
        emit grantProposed(orgId, proposedGrantId, grantee, unlockTime, tokens);
        //shortcut for orgs that only require one confirmation
        if (requiredConfirmations[orgId] == 1) {
            _activeGrantId.increment();
            activeGrants[_activeGrantId.current()] = Grant(
                orgId,
                grantee,
                unlockTime,
                tokens,
                rawGrantee
            );
            for (uint256 i = 0; i < tokens.tokens.length; ++i) {
                balances[orgId][tokens.tokens[i]] -= tokens.amounts[i];
            }
            grantedGrantList[orgId].push(_activeGrantId.current());
            pendingGrantList[grantee].push(_activeGrantId.current());
            emit grantActivated(
                orgId,
                proposedGrantId,
                proposedGrants[orgId][proposedGrantId].proposedGrant.grantee,
                _activeGrantId.current(),
                proposedGrants[orgId][proposedGrantId].proposedGrant.unlockTime,
                proposedGrants[orgId][proposedGrantId].proposedGrant.tokens
            );
        } else {
            proposedGrants[orgId][proposedGrantId] = grantProp(
                Grant(orgId, grantee, unlockTime, tokens, rawGrantee),
                Counters.Counter(1)
            );
        }
    }

    function confirmGrant(uint256 orgId, uint256 grantId)
        public
        onlyMember(orgId)
    {
        require(votedGrant[orgId][grantId][msg.sender] == false);
        proposedGrants[orgId][grantId].confirmations.increment();
        votedGrant[orgId][grantId][msg.sender] = true;
        require(
            proposedGrants[orgId][grantId].confirmations.current() <=
                requiredConfirmations[orgId],
            "grant has already been activated"
        );
        if (
            proposedGrants[orgId][grantId].confirmations.current() ==
            requiredConfirmations[orgId]
        ) {
            for (
                uint256 i = 0;
                i <
                proposedGrants[orgId][grantId]
                    .proposedGrant
                    .tokens
                    .tokens
                    .length;
                ++i
            ) {
                balances[orgId][
                    proposedGrants[orgId][grantId].proposedGrant.tokens.tokens[
                        i
                    ]
                ] -= proposedGrants[orgId][grantId]
                    .proposedGrant
                    .tokens
                    .amounts[i];
            }

            _activeGrantId.increment();
            activeGrants[_activeGrantId.current()] = proposedGrants[orgId][
                grantId
            ].proposedGrant;
            grantedGrantList[orgId].push(_activeGrantId.current());
            if (proposedGrants[orgId][grantId].proposedGrant.grantee != 0) {
                pendingGrantList[
                    proposedGrants[orgId][grantId].proposedGrant.grantee
                ].push(_activeGrantId.current());
            } else {
                pendingGrantRawGrantList[
                    proposedGrants[orgId][grantId].proposedGrant.rawGrantee
                ].push(_activeGrantId.current());
            }
            emit grantActivated(
                orgId,
                grantId,
                proposedGrants[orgId][grantId].proposedGrant.grantee,
                _activeGrantId.current(),
                proposedGrants[orgId][grantId].proposedGrant.unlockTime,
                proposedGrants[orgId][grantId].proposedGrant.tokens
            );
        }
    }

    event revokeProposed(uint256 indexed revokeId, uint256 indexed grantId);
    event revokeActivated(uint256 indexed revokeId, uint256 indexed grantId);

    //this whole function is extremely gas inefficient. If this contract were to be deployed to mainnet
    //we would not go to the trouble of maintaining the grant indexes, which are why this function is so expensive
    //the frontend can survive without this indexing by querying several events with eth_getLogs and topic filters
    //but having to claim/cancel one at a time little bit of a pain that can be avoided as long as gas is cheap
    function revokeGrant(uint256 grantId, uint256 orgId) internal {
        //grantId of 0 means revoke all grants
        if (grantId == 0) {
            uint256 len = grantedGrantList[orgId].length;
            for (uint256 i = 0; i < len; ++i) {
                //so we don't bother trying to remove stuff that's already gone
                if (
                    grantedGrantList[orgId][i] != 0 &&
                    activeGrants[grantedGrantList[orgId][i]].unlockTime >
                    block.timestamp
                ) {
                    revokeGrant(grantedGrantList[orgId][i], orgId);
                }
            }
        } else {
            require(
                activeGrants[grantId].unlockTime > block.timestamp,
                "grant has already unlocked"
            );
            //at the end of (256-bit) unix time you can redeem the grant again
            activeGrants[grantId].unlockTime = ~uint256(0);
            //refund
            for (
                uint256 i = 0;
                i < activeGrants[grantId].tokens.tokens.length;
                ++i
            ) {
                balances[activeGrants[grantId].granter][
                    activeGrants[grantId].tokens.tokens[i]
                ] += activeGrants[grantId].tokens.amounts[i];
            }
            //rest of this just cleans up the indexes
            uint256 grantee = activeGrants[grantId].grantee;
            uint256 granter = activeGrants[grantId].granter;
            address rawGrantee = activeGrants[grantId].rawGrantee;
            for (uint256 i = 0; i < grantedGrantList[granter].length; ++i) {
                if (grantedGrantList[granter][i] == grantId) {
                    //zeroing the value is cheaper than shifting stuff
                    //and changing size would screw up our recursive batch grant removal up above
                    grantedGrantList[granter][i] = 0;
                }
            }
            for (uint256 i = 0; i < pendingGrantList[grantee].length; ++i) {
                if (pendingGrantList[grantee][i] == grantId) {
                    pendingGrantList[grantee][i] = 0;
                }
            }
            for (
                uint256 i = 0;
                i < pendingGrantRawGrantList[rawGrantee].length;
                ++i
            ) {
                if (pendingGrantRawGrantList[rawGrantee][i] == grantId) {
                    pendingGrantRawGrantList[rawGrantee][i] = 0;
                }
            }
        }
    }

    //                                     (active grant ID)
    function proposeGrantRevoke(uint256 orgId, uint256 grantId)
        public
        onlyMember(orgId)
    {
        proposedGrantRevokeIds[orgId].increment();

        emit revokeProposed(proposedGrantRevokeIds[orgId].current(), grantId);
        //shortcut for orgs that only require one confirmation
        if (requiredConfirmations[orgId] == 1) {
            revokeGrant(grantId, orgId);
            emit revokeActivated(
                proposedGrantRevokeIds[orgId].current(),
                grantId
            );
        } else {
            proposedGrantRevokes[orgId][
                proposedGrantRevokeIds[orgId].current()
            ] = grantRevokeProp(grantId, Counters.Counter(1));
        }
    }

    function confirmGrantRevoke(uint256 orgId, uint256 revokeId)
        public
        onlyMember(orgId)
    {
        require(
            proposedGrantRevokes[orgId][revokeId].confirmations.current() <=
                requiredConfirmations[orgId],
            "revoke has already been performed"
        );
        require(votedGrantRevoke[orgId][revokeId][msg.sender] == false);
        proposedGrantRevokes[orgId][revokeId].confirmations.increment();
        votedGrantRevoke[orgId][revokeId][msg.sender] = true;
        if (
            proposedGrantRevokes[orgId][revokeId].confirmations.current() ==
            requiredConfirmations[orgId]
        ) {
            revokeGrant(
                proposedGrantRevokes[orgId][revokeId].proposedIdToRevoke,
                orgId
            );
            emit revokeActivated(
                revokeId,
                proposedGrantRevokes[orgId][revokeId].proposedIdToRevoke
            );
        }
    }

    //this proposes a revoke of a grant with ID 0, which is interpreted by revokeGrant as a revoke of all grants
    //this can be done through proposeGrantRevoke as well, but this utility function improves UX
    //this is useful for orgs that need to exit all grants quickly
    //(e.g you're Su Zhu from 3ac and you're rugging all your grantees to pay your margin call)
    function proposeRevokeAll(uint256 orgId) public onlyMember(orgId) {
        proposeGrantRevoke(orgId, 0);
    }

    event grantClaimed(uint256 indexed grantId, uint256 indexed grantee);

    //you can claim a grant that isn't yours, but the tokens still go to the grantee
    function claimGrant(uint256 grantId) public {
        require(
            activeGrants[grantId].unlockTime < block.timestamp,
            "grant is still locked"
        );
        activeGrants[grantId].unlockTime = ~uint256(0);
        //signals that grantee is account
        if (activeGrants[grantId].grantee == 0) {
            for (
                uint256 i = 0;
                i < activeGrants[grantId].tokens.tokens.length;
                ++i
            ) {
                IERC20(activeGrants[grantId].tokens.tokens[i]).transfer(
                    activeGrants[grantId].rawGrantee,
                    activeGrants[grantId].tokens.amounts[i]
                );
            }
        }

        uint256 grantee = activeGrants[grantId].grantee;
        uint256 granter = activeGrants[grantId].granter;
        address rawGrantee = activeGrants[grantId].rawGrantee;
        if (grantee != 0) {
            for (
                uint256 i = 0;
                i < activeGrants[grantId].tokens.amounts.length;
                ++i
            ) {
                balances[grantee][
                    activeGrants[grantId].tokens.tokens[i]
                ] += activeGrants[grantId].tokens.amounts[i];
            }
        } else {
            for (
                uint256 i = 0;
                i < activeGrants[grantId].tokens.amounts.length;
                ++i
            ) {
                IERC20(activeGrants[grantId].tokens.tokens[i]).transfer(
                    rawGrantee,
                    activeGrants[grantId].tokens.amounts[i]
                );
            }
        }
        //clean up indexes
        for (uint256 i = 0; i < grantedGrantList[granter].length; ++i) {
            if (grantedGrantList[granter][i] == grantId) {
                //zeroing the value is cheaper than shifting stuff
                //and changing size would screw up our recursive batch grant removal up above
                grantedGrantList[granter][i] = 0;
            }
        }
        for (uint256 i = 0; i < pendingGrantList[grantee].length; ++i) {
            if (pendingGrantList[grantee][i] == grantId) {
                pendingGrantList[grantee][i] = 0;
            }
        }
        for (
            uint256 i = 0;
            i < pendingGrantRawGrantList[rawGrantee].length;
            ++i
        ) {
            if (pendingGrantRawGrantList[rawGrantee][i] == grantId) {
                pendingGrantRawGrantList[rawGrantee][i] = 0;
            }
        }
        emit grantClaimed(grantId, activeGrants[grantId].grantee);
    }

    //use grantee for orgs, rawGrantee for accounts, null the other
    function claimAll(uint256 grantee, address rawGrantee) public {
        if (grantee == 0) {
            for (
                uint256 i = 0;
                i < pendingGrantRawGrantList[rawGrantee].length;
                ++i
            ) {
                if (
                    activeGrants[pendingGrantRawGrantList[rawGrantee][i]]
                        .unlockTime <
                    block.timestamp &&
                    pendingGrantRawGrantList[rawGrantee][i] != 0
                ) {
                    claimGrant(pendingGrantRawGrantList[rawGrantee][i]);
                }
            }
        } else {
            for (uint256 i = 0; i < pendingGrantList[grantee].length; ++i) {
                if (
                    activeGrants[pendingGrantList[grantee][i]].unlockTime <
                    block.timestamp &&
                    pendingGrantList[grantee][i] != 0
                ) {
                    claimGrant(pendingGrantList[grantee][i]);
                }
            }
        }
    }
}
