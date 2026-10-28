-- ID proofs are visible to office bearers, the related owner/requester, and the assigned approver/POC.
drop policy id_docs_read on id_documents;
create policy id_docs_read on id_documents for select using (
  is_member(association_id) and (
    has_role(association_id,array[
      'admin','president','secretary','treasurer','vice_president','joint_secretary','joint_treasurer'
    ]::app_role[])
    or uploaded_by=auth.uid()
    or owns_flat(flat_id::text)
    or exists(
      select 1 from approval_requests r
      where r.id=id_documents.request_id and r.association_id=id_documents.association_id
        and r.initiator=auth.uid()
    )
    or exists(
      select 1 from approval_steps s join approval_requests r on r.id=s.request_id
      where s.request_id=id_documents.request_id and r.association_id=id_documents.association_id
        and s.approver=auth.uid()
    )
  )
);

-- The existing storage policy delegates reads through id_documents RLS; replace it explicitly
-- so the policy's intent stays visible beside the document-level access rule.
drop policy id_proofs_read on storage.objects;
create policy id_proofs_read on storage.objects for select to authenticated using (
  bucket_id='id-proofs' and exists(
    select 1 from id_documents d where d.storage_path=name and d.association_id=my_association()
  )
);
