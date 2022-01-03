from brownie import accounts, network, config

LOCAL_BLOCKCHAIN_ENVIRONMENTS = [
    "development",
    "ganache",
    "hardhat",
    "local-ganache",
    "mainnet-fork",
]

def get_account(index=None):
    """
    Get given ethereum wallet:
        - if index called, get account[index]
        - if local environment, get account[0]
        - else, load test-account from brownie
    """
    if index:
        return accounts[index]
    if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        print(accounts[0].balance())
        return accounts[0]
    # Change for main deployment!
    return accounts.load("test-account")
