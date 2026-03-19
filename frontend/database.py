"""Database placeholders for prototype mode.

MongoDB integration has been removed from this module while Flutter uses
Firestore directly.
"""

users_collection = None
ambulance_collection = None


async def init_db():
    return None
