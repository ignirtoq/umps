class NotConnectedError(Exception):
    """
    Exception thrown when an interface is not connected to a socket.
    """


class NotSubscribedError(Exception):
    """
    Exception thrown when attempting to unsubscribe from a topic the
    interface is not currently subscribed to.
    """
