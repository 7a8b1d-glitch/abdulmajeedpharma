"""SQLAlchemy models for the APH backend.

All models are defined in separate files under app/models/ and re-exported
here for convenient importing. The models mirror the SQL migrations under
database/migrations/ (001 through 011).
"""

from app.models.base import Base
from app.models.countries import Country
from app.models.body_systems import BodySystem
from app.models.therapeutic_classes import TherapeuticClass
from app.models.pharmacological_classes import PharmacologicalClass
from app.models.drug_classes import DrugClass
from app.models.active_ingredients import ActiveIngredient
from app.models.drug import Drug
from app.models.drug_ingredients import DrugIngredient
from app.models.drug_class_links import DrugClassLink
from app.models.drug_indications import DrugIndication
from app.models.drug_contraindications import DrugContraindication
from app.models.drug_adverse_effects import DrugAdverseEffect
from app.models.drug_interactions import DrugInteraction
from app.models.drug_dosage_information import DrugDosageInformation
from app.models.drug_special_populations import DrugSpecialPopulation
from app.models.drug_images import DrugImage
from app.models.manufacturers import Manufacturer
from app.models.marketing_authorization_holders import MarketingAuthorizationHolder
from app.models.suppliers import Supplier
from app.models.distributors import Distributor
from app.models.brand_products import BrandProduct
from app.models.product_presentations import ProductPresentation
from app.models.product_markets import ProductMarket
from app.models.product_registration_records import ProductRegistrationRecord
from app.models.scientific_sources import ScientificSource
from app.models.drug_evidence import DrugEvidence
from app.models.content_reviews import ContentReview
from app.models.user_profiles import UserProfile
from app.models.conversations import Conversation
from app.models.conversation_participants import ConversationParticipant
from app.models.messages import Message
from app.models.message_attachments import MessageAttachment
from app.models.message_read_receipts import MessageReadReceipt
from app.models.notifications import Notification
from app.models.import_batches import ImportBatch
from app.models.import_batch_items import ImportBatchItem
from app.models.import_errors import ImportError
from app.models.audit_logs import AuditLog
from app.models.sync_records import SyncRecord

__all__ = [
    "Base",
    "Country",
    "BodySystem",
    "TherapeuticClass",
    "PharmacologicalClass",
    "DrugClass",
    "ActiveIngredient",
    "Drug",
    "DrugIngredient",
    "DrugClassLink",
    "DrugIndication",
    "DrugContraindication",
    "DrugAdverseEffect",
    "DrugInteraction",
    "DrugDosageInformation",
    "DrugSpecialPopulation",
    "DrugImage",
    "Manufacturer",
    "MarketingAuthorizationHolder",
    "Supplier",
    "Distributor",
    "BrandProduct",
    "ProductPresentation",
    "ProductMarket",
    "ProductRegistrationRecord",
    "ScientificSource",
    "DrugEvidence",
    "ContentReview",
    "UserProfile",
    "Conversation",
    "ConversationParticipant",
    "Message",
    "MessageAttachment",
    "MessageReadReceipt",
    "Notification",
    "ImportBatch",
    "ImportBatchItem",
    "ImportError",
    "AuditLog",
    "SyncRecord",
]
